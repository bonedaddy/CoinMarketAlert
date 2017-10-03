pragma solidity 0.4.16;

// Used for function invoke restriction
contract Owned {

    address public owner; // temporary address
    address public alertCreator;

    function Owned() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner)
            revert();
        _; // function code inserted here
    }

    modifier onlyAlertCreator() {
        require(msg.sender == alertCreator);
        _;
    }

    function transferOwnership(address _newOwner) onlyOwner returns (bool success) {
        if (msg.sender != owner)
            revert();
        owner = _newOwner;
        return true;
        
    }

    function transferAlertCreator(address _newCreator) onlyOwner returns (bool success) {
        require(_newCreator != owner);
        require(_newCreator != msg.sender);
        alertCreator = _newCreator;
        return true;
    }
}

contract SafeMath {

    function mul(uint256 a, uint256 b) internal constant returns (uint256) {
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal constant returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }

    function sub(uint256 a, uint256 b) internal constant returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal constant returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }
}


contract CoinMarketAlert is Owned, SafeMath {

    address     public      payoutContractAddress;
    uint256     public      totalSupply;
    uint256     public      nextPayoutDay;
    uint256     public      nextNextPayoutDay;
    uint256     public      weekNumber;
    uint256     public      creationBonus;
    uint256     public      alertsCreated;
    uint256     public      usersRegistered;
    uint256     private     weekIDs;
    uint8       public      decimals;
    bytes20     public      weekIdentifierHash;
    bytes20[]   public      weekIdentifierHashArray;
    string      public      name;
    string      public      symbol;
    bool        public      tokenTransfersFrozen;
    bool        public      tokenMintingEnabled;


    struct AlertCreatorStruct {
        address alertCreator;
        uint256 alertsCreated;
    }

    AlertCreatorStruct[]   public      alertCreators;
    
    // Used to keep track of the AlertCreatorStruct IDs for a user
    mapping (address => uint256) public alertCreatorId;
    // Alert Creator Entered (Used to prevetnt duplicates in creator array)
    mapping (address => bool) public userRegistered;
    // Tracks approval
    mapping (address => mapping (address => uint256)) public allowance;
    //[addr][balance]
    mapping (address => uint256) public balances;
    //[addr][week ID Hash][balance]
    mapping (address => mapping (uint256 => uint256)) public pendingBalances;
    //[addr][week ID Hash][balance]
    mapping (address => mapping (uint256 => uint256)) public paidBalances;
    // Tracks Week Identifier Array Index to it's bytes20 ripemd hash
    mapping (uint256 => bytes20) public weekHashArrayIndexTracker;

    event Transfer(address indexed _from, address indexed _to, uint256 _amount);
    event Approve(address indexed _owner, address indexed _spender, uint256 _amount);
    event MintTokens(address indexed _minter, uint256 _amountMinted, bool indexed Minted);
    event AlertCreated(address indexed _creator, uint256 _alertsCreated, bool indexed _alertCreated);
    event EnableTokenMinting(bool Enabled);

    function CoinMarketAlert() {
        symbol = "CMA";
        name = "Coin Market Alert";
        decimals = 18;
        // 1 in wei
        creationBonus = 1000000000000000000;
        // 50 Mil in wei
        totalSupply = 50000000000000000000000000;
        balances[msg.sender] = add(balances[msg.sender], totalSupply);
        tokenTransfersFrozen = true;
        tokenMintingEnabled = false;
    }

    /// @notice Used to launch, enable token transfers and token minting, start week counting
    function launchContract() onlyOwner returns (bool launched) {
        tokenTransfersFrozen = false;
        tokenMintingEnabled = true;
        nextPayoutDay = now + 1 weeks;
        nextNextPayoutDay = now + 2 weeks;
        weekIdentifierHash = ripemd160(nextPayoutDay);
        weekIdentifierHashArray.push(weekIdentifierHash);
        weekIDs = 0;
        weekHashArrayIndexTracker[0] = weekIdentifierHash;
        EnableTokenMinting(true);
        return true;
    }

    /// @notice multi-user payout function, currently broken
    function payoutUsers(uint256 _weekIdentifier) onlyOwner returns (bool paid) {
        for (uint256 i = 0; i < usersRegistered; i++) {
            if (pendingBalances[alertCreators[i].alertCreator][_weekIdentifier] > 0) {
                address _receiver = alertCreators[i].alertCreator;
                uint256 _amountPay = pendingBalances[_receiver][_weekIdentifier];
                pendingBalances[_receiver][_weekIdentifier] = 0;
                paidBalances[_receiver][_weekIdentifier] = add(paidBalances[_receiver][_weekIdentifier], _amountPay);
                balances[_receiver] = add(balances[_receiver], _amountPay);
                _receiver.transfer(_amountPay);
                Transfer(owner, _receiver, _amountPay);
            }
        }
        return true;
    }

    /// @notice single user payout function
    function singlePayout(uint256 _weekIdentifier, address _user) onlyOwner returns (bool paid) {
        require(pendingBalances[_user][_weekIdentifier] > 0);
        uint256 _amountReceive = pendingBalances[_user][_weekIdentifier];
        pendingBalances[_user][_weekIdentifier] = 0;
        paidBalances[_user][_weekIdentifier] = add(paidBalances[_user][_weekIdentifier], _amountReceive);
        balances[_user] = add(balances[_user], _amountReceive);
        Transfer(owner, _user, _amountReceive);
        return true;
    }

    function registerUser(address _user) private returns (bool registered) {
        usersRegistered = add(usersRegistered, 1);
        AlertCreatorStruct memory acs;
        acs.alertCreator = _user;
        alertCreators.push(acs);
        userRegistered[_user] = true;
        return true;
    }

    function createAlert(address _creator) onlyOwner {
        if (now > nextPayoutDay) {
            nextPayoutDay = add(now, 1 weeks);
            weekIdentifierHash = ripemd160(nextPayoutDay);
            weekIdentifierHashArray.push(weekIdentifierHash);
            weekIDs = add(weekIDs, 1);
            weekHashArrayIndexTracker[weekIDs] = weekIdentifierHash;
        }
        if (!userRegistered[_creator]) {
            // register user who hasn't been seen by the system 
            registerUser(_creator);
        }
        alertCreators[alertCreatorId[_creator]].alertsCreated += 1;
        pendingBalances[_creator][weekIDs] = add(pendingBalances[_creator][weekIDs], creationBonus);
        AlertCreated(_creator, 1, true);
        alertsCreated = add(alertsCreated, 1);
    }



    /// @notice low-level minting function
    function tokenMint(address _invoker, uint256 _amount) private returns (bool raised) {
        require(_amount > 0);
        totalSupply = add(totalSupply, _amount);
        balances[owner] = add(balances[owner], _amount);
        Transfer(0, owner, _amount);
        MintTokens(_invoker, _amount, true);
        return true;
    }

    function tokenFactory(uint256 _amount) onlyOwner returns (bool success) {
        require(tokenMintingEnabled);
        if (!tokenMint(msg.sender, _amount)) {
            revert();
        } else {
            return true;
        }

    }    
    /// @notice low-level reusable function to prevent balance overflow when sending a transfer
    // and ensure all conditions are valid for a successful transfer
    function transferCheck(address _sender, address _receiver, uint256 _value) 
        private 
        returns (bool safe) 
    {
        require(_value > 0);
        // prevents empty receiver
        require(_receiver != address(0));
        require(sub(balances[_sender], _value) >= 0);
        require(add(balances[_receiver], _value) > balances[_receiver]);
        return true;
    }
    /// @notice Used to transfer funds
    function transfer(address _receiver, uint256 _amount) {
        require(!tokenTransfersFrozen);
        if (transferCheck(msg.sender, _receiver, _amount)) {
            balances[msg.sender] = sub(balances[msg.sender], _amount);
            balances[_receiver] = add(balances[_receiver], _amount);
            Transfer(msg.sender, _receiver, _amount);
        } else {
            // ensure we refund gas costs
            revert();
        }
    }

    /// @notice Used to transfer funds on behalf of one person
    function transferFrom(address _owner, address _receiver, uint256 _amount) {
        require(!tokenTransfersFrozen);
        require(sub(allowance[_owner][msg.sender], _amount) >= 0);
        if (transferCheck(_owner, _receiver, _amount)) {
            balances[_owner] = sub(balances[_owner], _amount);
            balances[_receiver] = add(balances[_receiver], _amount);
            allowance[_owner][_receiver] = sub(allowance[_owner][_receiver], _amount);
            Transfer(_owner, _receiver, _amount);
        } else {
            // ensure we refund gas costs
            revert();
        }
    }

    /// @notice Used to approve a third-party to send funds on your behalf
    function approve(address _spender, uint256 _amount) returns (bool approved) {
        require(_amount > 0);
        require(balances[msg.sender] > 0);
        allowance[msg.sender][_spender] = _amount;
        return true;
    }

     //GETTERS//
    ///////////

    /// @param _arrayIndex (starting at 0) the index ID of the array containing the ripemd week hashes
    function lookupWeekIdentifier(uint256 _arrayIndex) constant returns (bytes20 _identifier) {
        return weekIdentifierHashArray[_arrayIndex];
    }

    /// @notice Used to retrieve total supply
    function totalSupply() constant returns (uint256 _totalSupply) {
        return totalSupply;
    }

    /// @notice Used to look up balance of a user
    function balanceOf(address _person) constant returns (uint256 balance) {
        return balances[_person];
    }

    /// @notice Used to look up allowance of a user
    function allowance(address _owner, address _spender) constant returns (uint256 allowed) {
        return allowance[_owner][_spender];
    }
}


