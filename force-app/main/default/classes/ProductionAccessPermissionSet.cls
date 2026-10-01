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
            ];

            if (!existingPsa.isEmpty()) {
                res.isAlreadyAssigned = true;
                res.isSuccess = true;
                res.existingExpirationDate = existingPsa[0].ExpirationDate;
                res.message = 'Permission set is already assigned.';
                if (request.requestId != null) {updateRequestRecordFuture(request.requestId, existingPsa[0].Id);
                }
            } else {
                PermissionSetAssignment psa = new PermissionSetAssignment(
                    AssigneeId = request.userId,
                    PermissionSetId = resolvedPermSetId
                );
                if (request.expirationDate != null) {
                    psa.ExpirationDate = request.expirationDate;
                }

                PermissionSetAssignmentWrapper wrapper = new PermissionSetAssignmentWrapper();
                wrapper.assignment = psa;
                wrapper.requestId = request.requestId;
                assignmentsToInsert.add(wrapper);

                res.isAlreadyAssigned = false;
                res.isSuccess = true;
                res.existingExpirationDate = request.expirationDate;
                res.message = 'Permission set assigned successfully.';
            }

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
                for (PermissionSetAssignmentWrapper w : assignmentsToInsert) {
                    if (w.requestId != null && w.assignment.Id != null) {updateRequestRecordFuture(w.requestId, w.assignment.Id);
                    }
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
                Set<Id> assigneeIds = new Set<Id>();
                Set<Id> permSetIds = new Set<Id>();
                for (PermissionSetAssignmentWrapper w : wrappers) {
                    if (w.assignment != null) {
                        assigneeIds.add(w.assignment.AssigneeId);
                        permSetIds.add(w.assignment.PermissionSetId);
                    }
                }

                Map<String, PermissionSetAssignment> existingMap = new Map<String, PermissionSetAssignment>();
                if (!assigneeIds.isEmpty() && !permSetIds.isEmpty()) {
                    for (PermissionSetAssignment psa : [
                        SELECT Id, AssigneeId, PermissionSetId, ExpirationDate
                        FROM PermissionSetAssignment
                        WHERE AssigneeId IN :assigneeIds
                          AND PermissionSetId IN :permSetIds
                    ]) {
                        existingMap.put(psa.AssigneeId + '_' + psa.PermissionSetId, psa);
                    }
                }

                List<PermissionSetAssignment> toInsert = new List<PermissionSetAssignment>();
                List<PermissionSetAssignment> toUpdate = new List<PermissionSetAssignment>();

                for (PermissionSetAssignmentWrapper w : wrappers) {
                    if (w.assignment != null) {
                        String key = w.assignment.AssigneeId + '_' + w.assignment.PermissionSetId;
                        if (existingMap.containsKey(key)) {
                            PermissionSetAssignment existing = existingMap.get(key);
                            existing.ExpirationDate = w.assignment.ExpirationDate;
                            toUpdate.add(existing);
                            w.assignment = existing;
                        } else {
                            toInsert.add(w.assignment);
                        }
                    }
                }

                if (!toUpdate.isEmpty()) {
                    update toUpdate;
                }
                if (!toInsert.isEmpty()) {
                    Database.SaveResult[] saveResults = Database.insert(toInsert, false);

                    for (Integer i = 0; i < saveResults.size(); i++) {
                        if (!saveResults[i].isSuccess()) {
                            for (Database.Error err : saveResults[i].getErrors()) {
                                if (err.getStatusCode() == StatusCode.DUPLICATE_VALUE) {
                                    List<PermissionSetAssignment> existingList = [
                                        SELECT Id, ExpirationDate
                                        FROM PermissionSetAssignment
                                        WHERE AssigneeId = :toInsert[i].AssigneeId
                                          AND PermissionSetId = :toInsert[i].PermissionSetId
                                        LIMIT 1
                                    ];

                                    if (!existingList.isEmpty()) {existingList[0].ExpirationDate = toInsert[i].ExpirationDate;update existingList[0];
                                        toInsert[i] = existingList[0];
                                    } else {
                                        System.debug(LoggingLevel.WARN,
                                            'DUPLICATE_VALUE reported but no existing PSA found. AssigneeId: '
                                            + toInsert[i].AssigneeId + ', PermissionSetId: ' + toInsert[i].PermissionSetId
                                        );
                                    }
                                } else {
                                    throw new DmlException(err.getMessage());
                                }
                            }
                        }
                    }
                }

                for (PermissionSetAssignmentWrapper w : wrappers) {
                    if (w.requestId != null && w.assignment != null && w.assignment.Id != null) {
                        System.debug('in queable permissionSetAssignmentId: ' + w.assignment.Id);
                        updateRequestRecordFuture(w.requestId, w.assignment.Id);
                    }
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Queueable error: ' + e.getMessage());
                throw e;
            }
        }
    }

    @future
    public static void updateRequestRecordFuture(Id requestId, String psaId) {
        System.debug('code coming to future eith id of parid: '+requestId);
        System.debug('code coming to future eith id of permissionSetAssignmentId: '+psaId);
        if (requestId == null) {
            System.debug('code coming to future eith id of parid: '+requestId);
            return;
        }
        try {
            Production_Access_Request__c req = new Production_Access_Request__c(
                Id = requestId,
                Permission_Set_Assignment_Id__c = psaId,
                Status__c = 'Active'
            );
            update req;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error updating Production_Access_Request__c: ' + e.getMessage());
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