@RestResource(urlMapping='/productionAccess/approveReject/*')
global without sharing class ProductionAccessApprovalRestResource {

    @HttpGet
    global static void handleApprovalOrRejection() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        
        if (res == null) {
            res = new RestResponse();
            RestContext.response = res;
        }
        res.addHeader('Content-Type', 'text/html; charset=utf-8');

        String token = req.params.get('token');
        String recordId = req.params.get('id');
        String action = req.params.get('action');

        if (String.isNotBlank(token)) {
            recordId = decodeToken(token);
        }

        if (String.isBlank(recordId) || String.isBlank(action)) {
            res.responseBody = Blob.valueOf(generateHtmlResponse('Error', 'Invalid request parameters. Missing record ID/token or action.', false));
            return;
        }

        List<Production_Access_Request__c> requests = [
            SELECT Id, Status__c, Access_Type__c, Requested_Duration__c, Requested_Start__c, Requested_End__c, Developer_Email__c, Developer_Name__c, Ticket_Number__c
            FROM Production_Access_Request__c
            WHERE Id = :recordId
            LIMIT 1
        ];

        if (requests.isEmpty()) {
            res.responseBody = Blob.valueOf(generateHtmlResponse('Error', 'Production Access Request record not found.', false));
            return;
        }

        Production_Access_Request__c reqRecord = requests[0];

        if (reqRecord.Status__c != 'Pending Approval' && reqRecord.Status__c != 'Pending') {
            res.responseBody = Blob.valueOf(generateHtmlResponse('Notice', 'This request has already been processed with status: ' + reqRecord.Status__c, true));
            return;
        }

        if ('Approve'.equalsIgnoreCase(action) || 'Approved'.equalsIgnoreCase(action)) {
            reqRecord.Status__c = 'Approved';
            update reqRecord;
            res.responseBody = Blob.valueOf(generateHtmlResponse('Success', 'Production Access Request for ' + reqRecord.Developer_Name__c + ' has been APPROVED successfully.', true));
        } else if ('Reject'.equalsIgnoreCase(action) || 'Rejected'.equalsIgnoreCase(action)) {
            reqRecord.Status__c = 'Rejected';
            update reqRecord;
            res.responseBody = Blob.valueOf(generateHtmlResponse('Rejected', 'Production Access Request for ' + reqRecord.Developer_Name__c + ' has been REJECTED.', false));
        } else {
            res.responseBody = Blob.valueOf(generateHtmlResponse('Error', 'Invalid action parameter specified.', false));
        }
    }

    private static String generateHtmlResponse(String title, String message, Boolean isSuccess) {
        String headerColor = isSuccess ? '#2e7d32' : '#c62828';
        String badgeBgColor = isSuccess ? '#e8f5e9' : '#ffebee';
        String icon = isSuccess ? '&#10004;' : '&#10008;';

        String htmlStr = '<!DOCTYPE html><html><head><meta name="viewport" content="width=device-width, initial-scale=1.0"><title>' + title + '</title>' +
            '<style>' +
            'body { font-family: sans-serif; background-color: #f4f6f9; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }' +
            '.card { background: #ffffff; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.08); padding: 40px 30px; text-align: center; max-width: 480px; width: 100%; }' +
            '.icon { font-size: 48px; color: ' + headerColor + '; margin-bottom: 16px; }' +
            'h2 { color: #1e293b; margin: 0 0 12px 0; font-size: 24px; font-weight: 700; }' +
            'p { color: #64748b; font-size: 16px; line-height: 1.5; margin: 0 0 24px 0; }' +
            '.badge { display: inline-block; padding: 6px 16px; border-radius: 20px; font-weight: 600; font-size: 14px; background-color: ' + badgeBgColor + '; color: ' + headerColor + '; }' +
            '</style></head><body>' +
            '<div class="card">' +
            '<div class="icon">' + icon + '</div>' +
            '<h2>' + title + '</h2>' +
            '<p>' + message + '</p>' +
            '<div class="badge">Status Updated</div>' +
            '</div></body></html>';

        return htmlStr;
    }

    public static String encodeToken(String recordId) {
        if (String.isBlank(recordId)) {
            return '';
        }
        Long timestamp = System.currentTimeMillis();
        String rawPayload = recordId + ':' + timestamp;
        return EncodingUtil.urlEncode(EncodingUtil.base64Encode(Blob.valueOf(rawPayload)), 'UTF-8');
    }

    public static String decodeToken(String token) {
        if (String.isBlank(token)) {
            return null;
        }
        try {
            String decodedUrl = EncodingUtil.urlDecode(token, 'UTF-8');
            Blob decodedBlob = EncodingUtil.base64Decode(decodedUrl);
            String rawPayload = decodedBlob.toString();
            List<String> parts = rawPayload.split(':');
            if (!parts.isEmpty()) {
                return parts[0];
            }
        } catch (Exception e) {
            System.debug('Token decoding failed: ' + e.getMessage());
        }
        return null;
    }
}