// SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IPrimusZkTLS, Attestation, AttNetworkRequest, AttNetworkResponseResolve, Attestor} from "./IPrimusZkTLS.sol";

/**
 * @dev Implementation of the {IPrimusZkTLS} interface, providing 
 * functionality to encode and verify attestations.
 *
 * This contract also inherits {OwnableUpgradeable} to enable ownership control,
 * allowing for upgradeable contract management.
 */
contract PrimusZkTLS is OwnableUpgradeable, IPrimusZkTLS {
    // Mapping to store attestors for each address
    mapping(address => Attestor) public _attestorsMapping;
    Attestor[] public _attestors;

     /**
     * @dev initialize function to set the owner of the contract.
     * This function is called during the contract deployment.
     */
    function initialize(address _owner) public initializer {
        __Ownable_init(_owner);
        setupDefaultAttestor(_owner);
    }

    function setupDefaultAttestor(address defaultAddr) internal {
        require(defaultAddr != address(0), "Invalid address");
        _attestorsMapping[defaultAddr] = Attestor({
            attestorAddr: defaultAddr,
            url: "Default metadata"
        });
        _attestors.push(Attestor({
            attestorAddr: defaultAddr,
            url: "Default metadata"
        }));
    }

    /**
     * @dev Allows the owner to set the attestor for a specific recipient.
     *
     * Requirements:
     * - The caller must be the owner of the contract.
     *
     * 
     * @param attestor The attestor to associate with the recipient.
     */
    function setAttestor(Attestor calldata attestor) external onlyOwner {
        require(attestor.attestorAddr != address(0), "Attestor address cannot be zero");
        if(_attestorsMapping[attestor.attestorAddr].attestorAddr == address(0) ) {
            _attestors.push(attestor);
        }
        // Set the attestor for the recipient
        _attestorsMapping[attestor.attestorAddr] = attestor;
    }

    /**
     * @dev Removes the attestor for a specific recipient.
     *
     * Requirements:
     * - The caller must be the owner of the contract.
     *          attestorAddr
     * @param attestorAddr The address of the recipient whose attestor is to be removed.
     */
    function removeAttestor(address attestorAddr) external onlyOwner {
        require(attestorAddr != address(0), "Recipient address cannot be zero");
        require(_attestorsMapping[attestorAddr].attestorAddr != address(0), "No attestor found for the recipient");
        delete _attestorsMapping[attestorAddr];

        // update _attestors 
        for (uint256 i = 0; i < _attestors.length; i++) {
            if (_attestors[i].attestorAddr == attestorAddr) {
                _attestors[i] = _attestors[_attestors.length - 1];  
                _attestors.pop();  
                break;
            }
         }
    }


    /**
     * @dev Verifies the validity of a given attestation.
     *
     * Requirements:
     * - Attestation must contain valid signatures from attestors.
     * - The data, request, and response must be consistent.
     * - The attestation must not be expired based on its timestamp.
     *
     * @param attestation The attestation data to be verified.
     */
    function verifyAttestation(Attestation calldata attestation) external view returns (bool) {
        require(attestation.signature.length == 1, "Invalid signature length");
        bytes memory signature = attestation.signature[0];
        require(signature.length == 65,"Invalid signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        require(v == 27 || v == 28, "Invalid signature v value");
        address attestorAddr = ecrecover(attestationEncode(attestation), v, r, s);
        for (uint256 i = 0; i < _attestors.length; i++) {
            address currentAddr = _attestors[i].attestorAddr;
            if (attestorAddr == currentAddr) {
                return true;
            }
        }
        return false;
    }


    /**
     * @dev Encodes an attestation into a bytes32 hash.
     *
     * The encoding includes all fields in the attestation structure,
     * ensuring a unique hash representing the data.
     *
     * @param attestation The attestation data to encode.
     * @return A bytes32 hash of the encoded attestation.
     */
    function attestationEncode(
        Attestation calldata attestation
    ) public pure returns (bytes32) {
        bytes memory encodeData = abi.encodePacked(
            attestation.recipient,
            encodeRequest(attestation.request),
            encodeResponse(attestation.reponse),
            attestation.data,
            attestation.attParameters,
            attestation.timestamp
        );
        return keccak256(encodeData);
    }

    /**
     * @dev Encodes a network request into a bytes32 hash.
     *
     * The encoding includes the URL, headers, HTTP method, and body of the request.
     *
     * @param request The network request to encode.
     * @return A bytes32 hash of the encoded network request.
     */
    function encodeRequest(
        AttNetworkRequest calldata request
    ) public pure returns (bytes32) {
        bytes memory encodeData = abi.encodePacked(
            request.url,
            request.header,
            request.method,
            request.body
        );
        return keccak256(encodeData);
    }


    /**
     * @dev Encodes a list of network response resolutions into a bytes32 hash.
     *
     * This iterates through the response array and encodes each field, creating
     * a unique hash representing the full response data.
     *
     * @param reponse The array of response resolutions to encode.
     * @return A bytes32 hash of the encoded response resolutions.
     */
    function encodeResponse(
        AttNetworkResponseResolve[] calldata reponse
    ) public pure returns (bytes32) {
        bytes memory encodeData;
        for (uint256 i = 0; i < reponse.length; i++) {
            encodeData = abi.encodePacked(
                encodeData,
                reponse[i].keyName,
                reponse[i].parseType,
                reponse[i].parsePath
            );
        }
        return keccak256(encodeData);
    }

}