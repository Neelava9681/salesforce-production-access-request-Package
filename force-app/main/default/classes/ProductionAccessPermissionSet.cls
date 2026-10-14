public without sharing class ProductionAccessPermissionSet {

    public static List<PermissionSetResult> assignPermissionSet(List<PermissionSetRequest> requests) {
        List<PermissionSetResult> results = new List<PermissionSetResult>();
        List<PermissionSetAssignmentWrapper> assignmentsToInsert = new List<PermissionSetAssignmentWrapper>();

        Set<String> permSetKeys = new Set<String>();
        for (PermissionSetRequest request : requests) {
            if (String.isNotBlank(request.permissionSetId)) {
                permSetKeys.add(request.permissionSetId);
            }
        }

        Map<String, Id> permSetMap = new Map<String, Id>();
        if (!permSetKeys.isEmpty()) {
            for (PermissionSet ps : [
                SELECT Id, Name, Label
                FROM PermissionSet
                WHERE Name = :permSetKeys
                   OR Label = :permSetKeys
            ]) {
                permSetMap.put(ps.Id, ps.Id);
                permSetMap.put(ps.Name, ps.Id);
                permSetMap.put(ps.Label, ps.Id);
            }
        }

        for (PermissionSetRequest request : requests) {
            PermissionSetResult res = new PermissionSetResult();
            System.debug('userId: '+request.userId);

            if (request.userId == null) {
                throw new IllegalArgumentException('Production User ID is required.');
            }

            if (String.isBlank(request.permissionSetId)) {
                throw new IllegalArgumentException('Permission Set ID is required.');
            }

            Id resolvedPermSetId = permSetMap.get(request.permissionSetId);
            if (resolvedPermSetId == null && request.permissionSetId instanceof Id) {
                resolvedPermSetId = (Id) request.permissionSetId;
            }

            if (resolvedPermSetId == null) {
                throw new IllegalArgumentException(
                    'Could not find Permission Set matching: ' + request.permissionSetId
                );
            }

            List<PermissionSetAssignment> existingPsa = [
                SELECT Id, ExpirationDate
                FROM PermissionSetAssignment
                WHERE AssigneeId = :request.userId
                AND PermissionSetId = :resolvedPermSetId
                LIMIT 1
                ALL ROWS
            ];

            // Declare wrapper here so idsToDelete can be set inside the existingPsa check below
            PermissionSetAssignmentWrapper wrapper = new PermissionSetAssignmentWrapper();

            if (!existingPsa.isEmpty()) {
                // Store the old PSA Id in the wrapper so the Queueable can delete
                // it BEFORE inserting the new one (prevents race condition / DUPLICATE_VALUE)
                wrapper.idsToDelete = new List<Id>{ existingPsa[0].Id };
                res.isAlreadyAssigned = true;
            } else {
                res.isAlreadyAssigned = false;
            }

            // Always insert a fresh PSA with the new expiration date
            PermissionSetAssignment psa = new PermissionSetAssignment(
                AssigneeId = request.userId,
                PermissionSetId = resolvedPermSetId
            );
            if (request.expirationDate != null) {
                psa.ExpirationDate = request.expirationDate;
            }

            wrapper.assignment = psa;
            wrapper.requestId = request.requestId;
            wrapper.accessType = request.permissionSetId;
            assignmentsToInsert.add(wrapper);

            res.isSuccess = true;
            res.existingExpirationDate = request.expirationDate;
            res.message = res.isAlreadyAssigned
                ? 'Existing assignment deleted. New assignment will be created with updated timing.'
                : 'Permission set assigned successfully.';

            results.add(res);

            System.debug('permission set assignment result: ' + res);
        }

        if (!assignmentsToInsert.isEmpty()) {
            if (System.isQueueable() || System.isFuture() || System.isBatch()) {
                List<PermissionSetAssignment> psaList = new List<PermissionSetAssignment>();
                for (PermissionSetAssignmentWrapper w : assignmentsToInsert) {
                    psaList.add(w.assignment);
                }
                insert psaList;

                // Update the related Production_Access_Request__c with the new PSA Id
                List<Production_Access_Request__c> requestsToUpdate = new List<Production_Access_Request__c>();
                for (PermissionSetAssignmentWrapper w : assignmentsToInsert) {
                    if (w.requestId != null && w.assignment.Id != null) {
                        requestsToUpdate.add(new Production_Access_Request__c(
                            Id = w.requestId,
                            Permission_Set_Assignment_Id__c = w.assignment.Id,
                            Status__c = 'Active'
                        ));
                    }
                }
                if (!requestsToUpdate.isEmpty()) {
                    update requestsToUpdate;
                }
            } else {
                System.enqueueJob(new AssignPermissionSetQueueable(assignmentsToInsert));
            }
        }

        return results;
    }

    public class PermissionSetAssignmentWrapper {
        public PermissionSetAssignment assignment;
        public Id requestId;
        public String accessType;
        public List<Id> idsToDelete;
    }

    public class AssignPermissionSetQueueable implements Queueable {
        private List<PermissionSetAssignmentWrapper> wrappers;

        public AssignPermissionSetQueueable(List<PermissionSetAssignmentWrapper> wrappers) {
            this.wrappers = wrappers;
        }

        public void execute(QueueableContext context) {
            System.debug('========== QUEUEABLE EXECUTE STARTED ==========');
            if (wrappers == null || wrappers.isEmpty()) {
                return;
            }

            try {
                // Step 1: Delete old PSAs first (sequential in same transaction — no race condition)
                Set<Id> psaIdsToDelete = new Set<Id>();
                for (PermissionSetAssignmentWrapper w : wrappers) {
                    if (w.idsToDelete != null && !w.idsToDelete.isEmpty()) {psaIdsToDelete.addAll(w.idsToDelete);
                    }
                }
                if (!psaIdsToDelete.isEmpty()) {
                    List<PermissionSetAssignment> toDelete = [
                        SELECT Id
                        FROM PermissionSetAssignment
                        WHERE Id IN :psaIdsToDelete
                        ALL ROWS
                    ];
                    if (!toDelete.isEmpty()) {
                        delete toDelete;
                        System.debug('Queueable: deleted old PSAs: ' + psaIdsToDelete);
                    }
                }

                // Step 2: Insert new PSAs (old ones are already gone)
                List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
                for (PermissionSetAssignmentWrapper w : wrappers) {
                    if (w.assignment != null) {
                        toInsert.add(w.assignment);
                    }
                }

                if (!toInsert.isEmpty()) {
                    Database.SaveResult[] saveResults = Database.insert(toInsert, false);

                    for (Integer i = 0; i < saveResults.size(); i++) {
                        if (!saveResults[i].isSuccess()) {
                            for (Database.Error err : saveResults[i].getErrors()) {
                                if (err.getStatusCode() != StatusCode.DUPLICATE_VALUE) {
                                    throw new DmlException(err.getMessage());
                                }
                                System.debug(LoggingLevel.WARN,
                                    'DUPLICATE_VALUE on insert for AssigneeId: '
                                    + toInsert[i].AssigneeId + ', PermissionSetId: ' + toInsert[i].PermissionSetId
                                );
                            }
                        }
                    }
                }

                // Collect PSA Ids, request Ids, and access types to pass to a
                // @future method — needed to avoid MIXED_DML_OPERATION error
                // (PermissionSetAssignment is a Setup object; Production_Access_Request__c is not)
                List<Id> requestIds = new List<Id>();
                List<String> newPsaIds = new List<String>();
                List<String> accessTypes = new List<String>();

                for (PermissionSetAssignmentWrapper w : wrappers) {
                    if (w.assignment != null && w.assignment.Id != null) {
                        requestIds.add(w.requestId);        // may be null, handled in future
                        newPsaIds.add(w.assignment.Id);
                        accessTypes.add(w.accessType);
                    }
                }

                if (!newPsaIds.isEmpty()) {
                    updateRequestsWithNewPsaIdFuture(requestIds, newPsaIds, accessTypes);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Queueable error: ' + e.getMessage());
                throw e;
            }
        }
    }

    @future
    public static void updateRequestsWithNewPsaIdFuture(
        List<Id> requestIds,
        List<String> newPsaIds,
        List<String> accessTypes
    ) {
        try {
            Set<Id> handledIds = new Set<Id>();
            List<Production_Access_Request__c> toUpdate = new List<Production_Access_Request__c>();

            // Update the specific new request records
            for (Integer i = 0; i < requestIds.size(); i++) {
                if (requestIds[i] != null && newPsaIds[i] != null) {
                    System.debug('Future: updating request ' + requestIds[i] + ' with PSA Id ' + newPsaIds[i]);
                    toUpdate.add(new Production_Access_Request__c(
                        Id = requestIds[i],
                        Permission_Set_Assignment_Id__c = newPsaIds[i],
                        Status__c = 'Active'
                    ));
                    handledIds.add(requestIds[i]);
                }
            }

            // Also update any OTHER active requests with the same Access_Type__c
            for (Integer i = 0; i < accessTypes.size(); i++) {
                if (accessTypes[i] != null && newPsaIds[i] != null) {
                    String psaId = newPsaIds[i];
                    String accessType = accessTypes[i];
                    for (Production_Access_Request__c req : [
                        SELECT Id
                        FROM Production_Access_Request__c
                        WHERE Status__c = 'Active'
                        AND Access_Type__c = :accessType
                        AND Id NOT IN :handledIds
                    ]) {
                        req.Permission_Set_Assignment_Id__c = psaId;
                        toUpdate.add(req);
                        handledIds.add(req.Id);
                    }
                }
            }

            if (!toUpdate.isEmpty()) {
                update toUpdate;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error updating Production_Access_Request__c with new PSA Id: ' + e.getMessage());
        }
    }

    public class RemovePermissionSetRequest {
        @InvocableVariable(label='Permission Set Assignment ID')
        public Id permissionSetAssignmentId;

        @InvocableVariable(label='User ID')
        public Id userId;

        @InvocableVariable(label='Access Type or Permission Set API Name')
        public String accessType;
    }

    @InvocableMethod(
        label='Remove Production Permission Set Assignment'
        description='Asynchronously removes a Permission Set Assignment record by ID or User ID & Access Type'
    )
    public static void removePermissionSetAssignment(List<RemovePermissionSetRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> psaIdsToDelete = new Set<Id>();
        List<Id> userIds = new List<Id>();
        List<String> permSetNames = new List<String>();

        for (RemovePermissionSetRequest req : requests) {
            if (req != null) {
                if (req.permissionSetAssignmentId != null) {
                    psaIdsToDelete.add(req.permissionSetAssignmentId);
                }
                if (req.userId != null && String.isNotBlank(req.accessType)) {
                    userIds.add(req.userId);
                    permSetNames.add(req.accessType.trim());
                }
            }
        }

        if (!psaIdsToDelete.isEmpty() || (!userIds.isEmpty() && !permSetNames.isEmpty())) {
            deletePermissionSetAssignmentsFuture(new List<Id>(psaIdsToDelete), userIds, permSetNames);
        }
    }

    @future
    public static void deletePermissionSetAssignmentsFuture(List<Id> psaIds, List<Id> userIds, List<String> permSetNames) {
        try {
            Set<Id> targetPsaIds = new Set<Id>();
            if (psaIds != null && !psaIds.isEmpty()) {
                targetPsaIds.addAll(psaIds);
            }

            if (userIds != null && !userIds.isEmpty() && permSetNames != null && !permSetNames.isEmpty()) {
                Set<Id> resolvedPermSetIds = new Set<Id>();
                for (PermissionSet ps : [
                    SELECT Id, Name, Label
                    FROM PermissionSet
                    WHERE Name IN :permSetNames OR Label IN :permSetNames
                ]) {
                    resolvedPermSetIds.add(ps.Id);
                }

                if (!resolvedPermSetIds.isEmpty()) {
                    for (PermissionSetAssignment psa : [
                        SELECT Id
                        FROM PermissionSetAssignment
                        WHERE AssigneeId IN :userIds AND PermissionSetId IN :resolvedPermSetIds
                        ALL ROWS
                    ]) {
                        targetPsaIds.add(psa.Id);
                    }
                }
            }

            if (!targetPsaIds.isEmpty()) {
                List<PermissionSetAssignment> existingAssignments = [
                    SELECT Id
                    FROM PermissionSetAssignment
                    WHERE Id IN :targetPsaIds
                    ALL ROWS
                ];

                if (!existingAssignments.isEmpty()) {
                    delete existingAssignments;
                    System.debug('========== PERMISSION SET ASSIGNMENTS DELETED SUCCESSFULLY ==========');
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error deleting PermissionSetAssignment records: ' + e.getMessage());
        }
    }

    public class PermissionSetRequest {
        public Id userId;
        public String permissionSetId;
        public Datetime expirationDate;
        public Id requestId;
    }

    public class PermissionSetResult {
        public Boolean isAlreadyAssigned;
        public Boolean isSuccess;
        public Datetime existingExpirationDate;
        public String message;
    }
}