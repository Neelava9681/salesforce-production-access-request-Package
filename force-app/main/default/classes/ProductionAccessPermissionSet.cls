public with sharing class ProductionAccessPermissionSet {

    @InvocableMethod(
        label='Assign Production Permission Set'
        description='Assigns the configured permission set to the fixed Production User'
    )
    public static List<PermissionSetResult> assignPermissionSet(
        List<PermissionSetRequest> requests
    ) {
        List<PermissionSetResult> results = new List<PermissionSetResult>();
        List<PermissionSetAssignment> assignmentsToInsert = new List<PermissionSetAssignment>();

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
                WHERE Id IN :permSetKeys
                   OR Name IN :permSetKeys
                   OR Label IN :permSetKeys
            ]) {
                permSetMap.put(ps.Id, ps.Id);
                permSetMap.put(ps.Name, ps.Id);
                permSetMap.put(ps.Label, ps.Id);
            }
        }

        for (PermissionSetRequest request : requests) {
            PermissionSetResult res = new PermissionSetResult();

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
            } else {
                PermissionSetAssignment psa = new PermissionSetAssignment(
                    AssigneeId = request.userId,
                    PermissionSetId = resolvedPermSetId
                );
                if (request.expirationDate != null) {
                    psa.ExpirationDate = request.expirationDate;
                }
                assignmentsToInsert.add(psa);

                res.isAlreadyAssigned = false;
                res.isSuccess = true;
                res.existingExpirationDate = request.expirationDate;
                res.message = 'Permission set assigned successfully.';
            }

            results.add(res);
        }

        if (!assignmentsToInsert.isEmpty()) {
            if (System.isQueueable() || System.isFuture() || System.isBatch()) {
                insert assignmentsToInsert;
            } else {
                System.enqueueJob(new AssignPermissionSetQueueable(assignmentsToInsert));
            }
        }

        return results;
    }

    public class AssignPermissionSetQueueable implements Queueable {
        private List<PermissionSetAssignment> assignments;

        public AssignPermissionSetQueueable(List<PermissionSetAssignment> assignments) {
            this.assignments = assignments;
        }

        public void execute(QueueableContext context) {
            if (assignments != null && !assignments.isEmpty()) {
                insert assignments;
            }
        }
    }

    public class PermissionSetRequest {

        @InvocableVariable(required=true)
        public Id userId;

        @InvocableVariable(required=true)
        public String permissionSetId;

        @InvocableVariable
        public Datetime expirationDate;
    }

    public class PermissionSetResult {

        @InvocableVariable
        public Boolean isAlreadyAssigned;

        @InvocableVariable
        public Boolean isSuccess;

        @InvocableVariable
        public Datetime existingExpirationDate;

        @InvocableVariable
        public String message;
    }
}