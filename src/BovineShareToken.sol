// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title BovineShareToken
/// @notice ERC20 token representing fractional ownership of a specific bovine NFT.
///         Each share represents 1/Nth ownership of the underlying cow.
contract BovineShareToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    address public immutable underlyingNft;
    uint256 public immutable tokenId;
    
    constructor(
        string memory name_,
        string memory symbol_,
        address _underlyingNft,
        uint256 _tokenId
    ) ERC20(name_, symbol_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        
        underlyingNft = _underlyingNft;
        tokenId = _tokenId;
    }
    
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
    
    function burnFrom(address account, uint256 amount) public {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}
