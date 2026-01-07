pragma solidity ^0.8.7;


// VRF dependency
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

// HTTP GET dependency
import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

// ECDSA signature dependency
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/cryptography/ECDSA.sol";


// SPDX-License-Identifier: UNLICENSED


contract ACME_6 is VRFConsumerBaseV2, ChainlinkClient, ConfirmedOwner {

// ACME related varaible: request info, cert info...
 struct certInfo {
     bytes pubKey;
     uint256 verified_timestamp;
     bool verified;
     bytes32 requestID;
 }

 struct request_info {
     string domain;
     bytes pubKey;
     uint256 request_timestamp;
     bool created;
     bool valid;
 }


 mapping(string => certInfo) public cert;

 mapping(bytes32 => request_info) public request; //requestID, the hash of (domainNonce + domain + pubKey)

 mapping(string => uint256) public domainCounter;  //to prevent replay

 mapping(bytes => bool) public pubKey_entry;

 mapping(bytes32 => uint256) public requestIDtoNonce2;

 // VRF relevant variable
 VRFCoordinatorV2Interface COORDINATOR;
 LinkTokenInterface LINKTOKEN;

 // vrf subscription ID.
 uint64 public s_subscriptionId;

  address vrfCoordinator = 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed;

 address LinkToken = 0x326C977E6efc84E512bB9C30f76E30c160eD06FB;

  bytes32 keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;

 uint32 callbackGasLimit = 500000;

 uint16 requestConfirmations = 3;

 uint32 numWords =  1;

 uint256[] public s_randomWords;

 
 mapping(bytes32 => uint256) public requestIDto_vrfID;
 mapping(uint256 => uint256[]) public vrfIDToRandomWords;
 
  address public s_owner;


// HTTP GET variable
 using Chainlink for Chainlink.Request;

 bytes32 private jobId;
 uint256 private fee;

 event RequestFulfilled(bytes32 indexed requestId, bytes indexed data);


 mapping(bytes32 => bytes32) public httpRequestId_to_requestID;

 mapping(bytes32 => bytes) public requestID_to_result;




 constructor() VRFConsumerBaseV2(vrfCoordinator) ConfirmedOwner(msg.sender){
   COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
   LINKTOKEN = LinkTokenInterface(LinkToken);
   s_owner = msg.sender;
   createNewSubscription();

   setChainlinkToken(0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
   setChainlinkOracle(0x40193c8518BB267228Fc409a613bDbD8eC5a97b3);
   jobId = "7da2702f37fd48e5b1b9a5715e3509b6";
   fee = (1 * LINK_DIVISIBILITY) / 10; // 0,1 * 10**18 (Varies by network and job)
 }

 // Assumes the subscription is funded sufficiently.
 function fundAndRequestRandomWords(bytes32 _requestID ) internal {

   (bool success) = LINKTOKEN.transferAndCall(address(COORDINATOR), 600000000000000, abi.encode(s_subscriptionId));

   require(success, "Link token payment failed");

   uint256 vrfID = COORDINATOR.requestRandomWords(
     keyHash,
     s_subscriptionId,
     requestConfirmations,
     callbackGasLimit,
     numWords
   );
  

   requestIDto_vrfID[_requestID] = vrfID;
 }

 function fulfillRandomWords(
     uint256 requestId,
     uint256[] memory randomWords
   ) internal override {

   vrfIDToRandomWords[requestId] = randomWords;
 }

 //MAJOR ISSUE NOW: private key stealer can use the key pair to register other domain?

 function submitRequest(string memory _domain, bytes memory _pubKey, bytes memory _signature) external {

   updateCert(_domain);

   bytes32 requestID = keccak256(abi.encodePacked(_domain, domainCounter[_domain], "REQUEST"));

  
   bool signature_verified = verifySignature(_signature, requestID, _pubKey);

   if(signature_verified && !request[requestID].created && !cert[_domain].verified
     && !pubKey_entry[_pubKey] && LINKTOKEN.allowance(address(msg.sender), address(this)) >= 600000000000000) {
       LINKTOKEN.transferFrom(address(msg.sender), address(this), 600000000000000);

       fundAndRequestRandomWords(requestID);

       request_info memory request_NewInfo = request_info({
           domain: _domain,
           pubKey: _pubKey,
           request_timestamp: block.timestamp,
           created: true,
           valid: true
       });
       request[requestID] = request_NewInfo;

       domainCounter[_domain]++ ;
   }

   pubKey_entry[_pubKey] = true;

 }


 function updateRequest (bytes32 _requestID) internal {
    
   if (block.timestamp - request[_requestID].request_timestamp > 120) {
       request[_requestID].valid = false;
   }
 }

 function updateCert (string memory _domain) internal {
   if (block.timestamp - cert[_domain].verified_timestamp > 60 /*cert validity*/) {
       cert[_domain].verified = false;
   }
 }



 function requestBytes(bytes32 _requestID) internal {
       Chainlink.Request memory req = buildChainlinkRequest(
           jobId,
           address(this),
           this.fulfillBytes.selector
       );
      
       req.add(
           "get",
           request[_requestID].domain
       );

       req.add("path", "./pki_validation");

       bytes32 httpRequestId = sendChainlinkRequest(req, fee);

       httpRequestId_to_requestID[httpRequestId] = _requestID;

   }

  
  
 function fulfillBytes(
       bytes32 requestId,
       bytes memory  result
   ) public recordChainlinkFulfillment(requestId) {
       emit RequestFulfilled(requestId, result);
      
       bytes32 _requestID = httpRequestId_to_requestID[requestId];
      
       requestID_to_result[_requestID] = result;       

       uint256 _vrfID = requestIDto_vrfID[_requestID];
       uint256 _Nonce_1 = vrfIDToRandomWords[_vrfID][0];

     
       bool signature_verified = verifySignature(result,
       keccak256(abi.encodePacked(_Nonce_1, requestIDtoNonce2[_requestID])), request[_requestID].pubKey);
  
       if (signature_verified) {

         cert[request[_requestID].domain].pubKey = request[_requestID].pubKey;
         cert[request[_requestID].domain].verified_timestamp = block.timestamp;
         cert[request[_requestID].domain].verified = true;
         cert[request[_requestID].domain].requestID = _requestID;
       }
    

     request[_requestID].valid = false;

  }



 function verify(bytes32 _requestID, uint256 _Nonce_2, bytes memory _signature) external {
  
   updateRequest(_requestID);

   requestIDtoNonce2[_requestID] = _Nonce_2;

   if (request[_requestID].created && request[_requestID].valid && !cert[request[_requestID].domain].verified &&
   LINKTOKEN.allowance(address(msg.sender), address(this)) >= 100000000000000000){

     bytes32 verifyConstruction = keccak256(abi.encodePacked(_requestID, "VERIFY"));

     bool signature_verified = verifySignature(_signature, verifyConstruction, request[_requestID].pubKey);


     if (signature_verified){

       LINKTOKEN.transferFrom(address(msg.sender), address(this), 100000000000000000);

       requestBytes(_requestID);
     }

   }

   //request[_requestID].valid = false;
 }


 function revoke(string memory _domain, bytes memory _signature) external {

   bytes32 revokeConstruction = keccak256(abi.encodePacked(cert[_domain].requestID, "REVOKE"));

   bool signature_verified = verifySignature(_signature, revokeConstruction, cert[_domain].pubKey);

   require (signature_verified);

   cert[_domain].verified = false;
 }



 function generateHash (uint256 n1, uint256 n2) public pure returns (bytes32) {
     return keccak256(abi.encodePacked(n1, n2));
 }


 function get_cert_pubKey (string memory _domain) public view returns (bytes memory) {
   return cert[_domain].pubKey;
 }

 function get_cert_verifiedStatus (string memory _domain) public view returns (bool) {
     return cert[_domain].verified;
 }

 function get_cert_verifiedTimestamp (string memory _domain) public view returns (uint256) {
     return cert[_domain].verified_timestamp;
 }


 function createNewSubscription() private onlyOwner {
   s_subscriptionId = COORDINATOR.createSubscription();
   // Add this contract as a consumer of its own subscription.
   COORDINATOR.addConsumer(s_subscriptionId, address(this));
 }



 function addConsumer(address consumerAddress) external onlySubscriptionOwner {
   // Add a consumer contract to the subscription.
   COORDINATOR.addConsumer(s_subscriptionId, consumerAddress);
 }

 function removeConsumer(address consumerAddress) external onlySubscriptionOwner {
   // Remove a consumer contract from the subscription.
   COORDINATOR.removeConsumer(s_subscriptionId, consumerAddress);
 }

 function cancelSubscription(address receivingWallet) external onlySubscriptionOwner {
   // Cancel the subscription and send the remaining LINK to a wallet address.
   COORDINATOR.cancelSubscription(s_subscriptionId, receivingWallet);
   s_subscriptionId = 0;
 }

 // Transfer this contract's funds to an address.
 // 1000000000000000000 = 1 LINK

 function renounceOwnership() external onlySubscriptionOwner {
   s_owner = 0x0000000000000000000000000000000000000000;
 }

 modifier onlySubscriptionOwner() {
   require(msg.sender == s_owner);
   _;
 }

 function getEthSignedMessageHash(bytes32 _messageHash)
       public
       pure
       returns (bytes32)
   {
       return
           keccak256(
               abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash)
           );
   }
  function verifySignature(bytes memory _signature, bytes32 _messageHash, bytes memory _pubKey)
 public pure returns (bool success) {

       bytes32 ethSignedMessageHash = getEthSignedMessageHash(_messageHash);

       (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
       address recovered = ECDSA.recover(
           ethSignedMessageHash, // messageHash
           v, // v
           r, // r
           s // s
       );
      
       bytes32 _hash = keccak256(abi.encodePacked(_pubKey));

       address derived = address(uint160(uint256(_hash)));

       if (derived == recovered) {
           success = true;
       } else {
           success = false;
       }
      
   }


 function splitSignature(bytes memory sig)
 public pure returns (bytes32 r, bytes32 s, uint8 v)
 {
     require(sig.length == 65, "invalid signature length");

     assembly {
           // first 32 bytes, after the length prefix
           r := mload(add(sig, 32))
           // second 32 bytes
           s := mload(add(sig, 64))
           // final byte (first byte of the next 32 bytes)
           v := byte(0, mload(add(sig, 96)))
     }
       // implicitly return (r, s, v)
 }

}



