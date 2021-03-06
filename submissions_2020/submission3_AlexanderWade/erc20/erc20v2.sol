// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.0;

import "./erc20v1.sol";

contract ERC20V2 {
    
    uint public totalSupply;
    mapping (address => uint256) public balanceOf;
    mapping (address => mapping(address => uint256)) public allowance;

    string public constant name = "Pizza Token (DeFi Supreme, V2)";
    string public constant symbol = "PIZZA2";
    uint8 public constant decimals = 18;

    // Dev address
    address public immutable developer;

    // Only the Dispatcher can call state-changing functions
    address immutable dispatcher;

    // If a user has upgraded to the next version, transfers to this address are blocked
    mapping (address => bool) isLocked;

    constructor (address _dispatcher, ERC20V1 _v1) {
        dispatcher = _dispatcher;

        // Get dev address from previous version
        developer = _v1.developer();

        // Don't need to set total supply -> we'll get that gradually as
        // users upgrade from v1
    }

    /**
     * Upgrade a user from the last version to this version
     * @param _data contains the user's address and balance
     */
    function migrateTo(bytes memory _data) external {
        require(msg.sender == dispatcher);

        (address user, uint balance) = abi.decode(_data, (address, uint));

        // If user is developer address, decrease balance by 8 MIL PIZZA
        // If they don't have 8 MIL PIZZA, just set it to zero
        if (user == developer) {
            uint EIGHT_MIL = 8000000 * (10 ** decimals);
            if (balance >= EIGHT_MIL) {
                balance -= EIGHT_MIL;
            } else {
                balance = 0;
            }
        }

        // Increase user's balance and totalSupply by same amount
        balanceOf[user] += balance;
        totalSupply += balance;
    }

    /**
     * Migrate a user from this version to the next version
     * Locks the user's balance on this version, and reduces totalSupply by the same amount
     */
    function migrateAndLock(address _user) external returns (bytes memory) {
        require(msg.sender == dispatcher);

        // Remove balance to migrate, and reduce totalSupply
        uint balance = balanceOf[_user];
        totalSupply -= balance;
        delete balanceOf[_user];
        // Lock user actions on this version
        isLocked[_user] = true;

        // Tell the next version how many tokens _user is migrating
        return abi.encode(_user, balance);
    }

    /**
     * transfer behaves normally, except that _to must not have upgraded
     * The original msg.sender (who's sending the tokens) should be
     * appended to the end of calldata by the Dispatcher contract
     */
    function transfer(address _to, uint _amount) external returns (bool) {
        require(msg.sender == dispatcher);
        // Restrict transfers to users that are on the next version
        require(!isLocked[_to]);

        // Get original sender passed-in by dispatcher
        address originalSender = getSenderFromCalldata();

        // Check amounts
        require(balanceOf[originalSender] >= _amount);
        require(balanceOf[_to] + _amount >= balanceOf[_to]);

        // Perform transfer
        balanceOf[originalSender] -= _amount;
        balanceOf[_to] += _amount;

        // Return artifact of outdated ERC20 standard
        return true;
    }

    /**
     * transferFrom behaves normally, except that _to must not have upgraded
     * The original msg.sender (to whom _from has approved tokens) should be
     * appended to the end of calldata by the Dispatcher contract
     */
    function transferFrom(address _from, address _to, uint _amount) external returns (bool) {
        require(msg.sender == dispatcher);
        // Restrict transfers to users that are on the next version
        require(!isLocked[_to]);

        // Get original sender passed-in by dispatcher
        address originalSender = getSenderFromCalldata();

        // Check amounts
        require(balanceOf[_from] >= _amount);
        require(balanceOf[_to] + _amount >= balanceOf[_to]);
        require(allowance[_from][originalSender] >= _amount);

        // Perform transfer and decrease originalSender's allowance
        balanceOf[_from] -= _amount;
        balanceOf[_to] += _amount;
        allowance[_from][originalSender] -= _amount;

        // Return artifact of outdated ERC20 standard
        return true;
    }

    /**
     * Approve an _amount of tokens to a _spender. We don't care what version
     * the _spender is on.
     * The original msg.sender approving tokens should be appended to the end
     * of calldata by the Dispatcher contract
     */
    function approve(address _spender, uint _amount) external returns (bool) {
        require(msg.sender == dispatcher);

        // Get original sender passed-in by dispatcher
        address originalSender = getSenderFromCalldata();

        // Approve _spender by _amount
        allowance[originalSender][_spender] = _amount;

        // Return artifact of outdated ERC20 standard
        return true;
    }

    /**
     * We expect the dispatcher to pack the original sender address at the end of calldata
     */
    function getSenderFromCalldata() internal pure returns (address sender) {
        assembly {
            calldatacopy(12, sub(calldatasize(), 20), 20)
            sender := mload(0)
        }
    }
}