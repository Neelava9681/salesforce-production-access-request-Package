public without sharing class ProductionAccessTokenGenerator {

    public class TokenRequest {
        @InvocableVariable(required=true)
        public String recordId;
    }

    public class TokenResult {
        @InvocableVariable
        public String token;
    }

    @InvocableMethod(
        label='Generate Approval Token'
        description='Encodes the Production Access Request Record ID with a timestamp into a URL-safe Base64 token for email Approve/Reject links'
    )
    public static List<TokenResult> generateToken(List<TokenRequest> requests) {
        List<TokenResult> results = new List<TokenResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }
        for (TokenRequest req : requests) {
            TokenResult res = new TokenResult();
            res.token = ProductionAccessApprovalRestResource.encodeToken(req.recordId);
            results.add(res);
        }
        return results;
    }
}