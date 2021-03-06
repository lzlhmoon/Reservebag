pragma solidity ^0.4.23;

import "./library/SafeMath.sol";
import "./library/NameFilter.sol";

import "./interface/PlayerBookReceiverInterface.sol";

contract PlayerBook {
    using NameFilter for string;
    using SafeMath for uint256;

    address public owner;

    uint256 public registrationFee_ = 0 sun;            // price to register a name

    mapping(uint256 => PlayerBookReceiverInterface) public games_;  // mapping of our game interfaces for sending your account info to games
    mapping(address => bytes32) public gameNames_;          // lookup a games name
    mapping(address => uint256) public gameIDs_;            // lokup a games ID

    uint256 public gID_;        // total number of games
    uint256 public pID_;        // total number of players

    mapping(address => uint256) public pIDxAddr_;          // (addr => pID) returns player id by address
    mapping(bytes32 => uint256) public pIDxName_;          // (name => pID) returns player id by name
    mapping(uint256 => Player) public plyr_;               // (pID => data) player data
    mapping(uint256 => mapping(bytes32 => bool)) public plyrNames_; // (pID => name => bool) list of names a player owns.  (used so you can change your display name amoungst any name you own)
    mapping(uint256 => mapping(uint256 => bytes32)) public plyrNameList_; // (pID => nameNum => name) list of names a player owns

    struct Player {
        address addr;
        bytes32 name;
        uint256 laff;
        uint256 names;
    }

    constructor()
        public
    {
        owner = msg.sender;

        // premine the dev names
        // No keys are purchased with this method, it's simply locking our addresses,
        // PID's and names for referral codes.
        plyr_[1].addr = msg.sender;
        plyr_[1].name = "legion";
        plyr_[1].names = 1;
        pIDxAddr_[msg.sender] = 1;
        pIDxName_["legion"] = 1;
        plyrNames_[1]["legion"] = true;
        plyrNameList_[1][1] = "legion";

        pID_ = 1;
    }

    modifier onlyOwner {
        assert(owner == msg.sender);
        _;
    }

    /**
     * @dev prevents contracts from interacting with ReserveBag 
     */
    modifier isHuman() {
        address _addr = msg.sender;
        require (_addr == tx.origin);

        uint256 _codeLength;

        assembly {_codeLength := extcodesize(_addr)}
        require(_codeLength == 0, "sorry humans only");
        _;
    }

    modifier isRegisteredGame()
    {
        require(gameIDs_[msg.sender] != 0);
        _;
    }

    // fired whenever a player registers a name
    event onNewName
    (
        uint256 indexed playerID,
        address indexed playerAddress,
        bytes32 indexed playerName,
        bool isNewPlayer,
        uint256 affiliateID,
        address affiliateAddress,
        bytes32 affiliateName,
        uint256 amountPaid,
        uint256 timeStamp
    );

    // (for UI & viewing things on etherscan)
    function checkIfNameValid(string _nameStr)
        public
        view
        returns(bool)
    {
        bytes32 _name = _nameStr.nameFilter();
        if(pIDxName_[_name] == 0)
            return true;
        else
            return false;
    }

// public functions ====================================
    /**
     * @dev registers a name.  UI will always display the last name you registered.
     * but you will still own all previously registered names to use as affiliate 
     * links.
     * - must pay a registration fee.
     * - name must be unique
     * - names will be converted to lowercase
     * - name cannot start or end with a space 
     * - cannot have more than 1 space in a row
     * - cannot be only numbers
     * - cannot start with 0x 
     * - name must be at least 1 char
     * - max length of 32 characters long
     * - allowed characters: a-z, 0-9, and space
     * -functionhash- 0x921dec21 (using ID for affiliate)
     * -functionhash- 0x3ddd4698 (using address for affiliate)
     * -functionhash- 0x685ffd83 (using name for affiliate)
     * @param _nameString players desired name
     * @param _affCode affiliate ID, address, or name of who refered you
     * @param _all set to true if you want this to push your info to all games 
     * (this might cost a lot of gas)
     */
    function registerNameXID(string _nameString, uint256 _affCode, bool _all)
        isHuman()
        public
        payable
    {
        // make sure name fees paid
        require(msg.value >= registrationFee_, "you have to pay the name fee");

        // filter name + condition checks
        bytes32 _name = NameFilter.nameFilter(_nameString);

        // set up address 
        address _addr = msg.sender;

        // determine if player is new or not
        (uint256 _pID, bool _isNewPlayer) = determinePID(_addr);

        // manage affiliate residuals
        // if no affiliate code was given, no new affiliate code was given, or the 
        // player tried to use their own pID as an affiliate code, lolz
        if(_affCode != 0 && _affCode != plyr_[_pID].laff && _affCode != _pID) {
            // update last affiliate 
            plyr_[_pID].laff = _affCode;
        } else if(_affCode == _pID) {
            _affCode = 0;
        }

        // register name 
        registerNameCore(_pID, _addr, _affCode, _name, _isNewPlayer, _all);
    }

    function registerNameXaddr(string _nameString, address _affCode, bool _all)
        isHuman()
        public
        payable
    {
        // make sure name fees paid
        require(msg.value >= registrationFee_, "you have to pay the name fee");

        // filter name + condition checks
        bytes32 _name = NameFilter.nameFilter(_nameString);

        // set up address 
        address _addr = msg.sender;

        // determine if player is new or not
        (uint256 _pID, bool _isNewPlayer) = determinePID(_addr);

        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        uint256 _affID;
        if(_affCode != address(0) && _affCode != _addr) {
            // get affiliate ID from aff Code 
            _affID = pIDxAddr_[_affCode];

            // if affID is not the same as previously stored 
            if(_affID != plyr_[_pID].laff) {
                // update last affiliate
                plyr_[_pID].laff = _affID;
            }
        }

        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all);
    }

    function registerNameXname(string _nameString, bytes32 _affCode, bool _all)
        isHuman()
        public
        payable 
    {
        // make sure name fees paid
        require(msg.value >= registrationFee_, "you have to pay the name fee");

        // filter name + condition checks
        bytes32 _name = NameFilter.nameFilter(_nameString);

        // set up address 
        address _addr = msg.sender;

        // determine if player is new or not
        (uint256 _pID, bool _isNewPlayer) = determinePID(_addr);

        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        uint256 _affID;
        if(_affCode != "" && _affCode != _name) {
            // get affiliate ID from aff Code 
            _affID = pIDxName_[_affCode];

            // if affID is not the same as previously stored 
            if(_affID != plyr_[_pID].laff) {
                // update last affiliate
                plyr_[_pID].laff = _affID;
            }
        }

        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all);
    }

    /**
     * @dev players, if you registered a profile, before a game was released, or
     * set the all bool to false when you registered, use this function to push
     * your profile to a single game.  also, if you've  updated your name, you
     * can use this to push your name to games of your choosing.
     * -functionhash- 0x81c5b206
     * @param _gameID game id 
     */
    function addMeToGame(uint256 _gameID)
        isHuman()
        public
    {
        require(gID_ > 0 && _gameID <= gID_, "that game doesn't exist yet");

        address _addr = msg.sender;

        uint256 _pID = pIDxAddr_[_addr];
        require(_pID != 0, "you dont even have an account");

        uint256 _totalNames = plyr_[_pID].names;

        // add players profile and most recent name
        games_[_gameID].receivePlayerInfo(_pID, _addr, plyr_[_pID].name);

        // add list of all names
        if(_totalNames > 1) {
            for (uint256 j = 1; j <= _totalNames; j++) {
                games_[_gameID].receivePlayerNameList(_pID, plyrNameList_[_pID][j]);
            }
        }
    }

    /**
     * @dev players, use this to push your player profile to all registered games.
     * -functionhash- 0x0c6940ea
     */
    function addMeToAllGames()
        isHuman()
        public
    {
        address _addr = msg.sender;

        uint256 _pID = pIDxAddr_[_addr];
        require(_pID != 0, "you dont even have an account");

        // uint256 _laff = plyr_[_pID].laff;
        uint256 _totalNames = plyr_[_pID].names;
        bytes32 _name = plyr_[_pID].name;

        for(uint256 i = 1; i <= gID_; i++) {
            games_[i].receivePlayerInfo(_pID, _addr, _name);
            if(_totalNames > 1) {
                for(uint256 j = 1; j <= _totalNames; j++) {
                    games_[i].receivePlayerNameList(_pID, plyrNameList_[_pID][j]);
                }
            }
        }
    }

    /**
     * @dev players use this to change back to one of your old names.  tip, you'll
     * still need to push that info to existing games.
     * -functionhash- 0xb9291296
     * @param _nameString the name you want to use 
     */
    function useMyOldName(string _nameString)
        isHuman()
        public 
    {
        // filter name, and get pID
        bytes32 _name = _nameString.nameFilter();
        uint256 _pID = pIDxAddr_[msg.sender];

        // make sure they own the name 
        require(plyrNames_[_pID][_name], "thats not a name you own");

        // update their current name 
        plyr_[_pID].name = _name;
    }

// core logic =========================================
    function registerNameCore(uint256 _pID, address _addr, uint256 _affID, bytes32 _name, bool _isNewPlayer, bool _all)
        private
    {
        // if names already has been used, require that current msg sender owns the name
        if(pIDxName_[_name] != 0) {
            require(plyrNames_[_pID][_name], "that name already taken");
        }

        // add name to player profile, registry, and name book
        plyr_[_pID].name = _name;
        pIDxName_[_name] = _pID;
        if(!plyrNames_[_pID][_name]) {
            plyrNames_[_pID][_name] = true;
            // plyr_[_pID].names++;
            uint256 namesCount = plyr_[_pID].names + 1;
            plyr_[_pID].names = namesCount;
            plyrNameList_[_pID][namesCount] = _name;
        }

        // registration fee goes directly to contract owner
        owner.transfer(msg.value);

        // push player info to games
        if(_all) {
            for(uint256 i = 1; i <= gID_; i++) {
                games_[i].receivePlayerInfo(_pID, _addr, _name);
            }
        }

        emit onNewName(_pID, _addr, _name, _isNewPlayer, _affID, plyr_[_affID].addr, plyr_[_affID].name, msg.value, now);
    }

// tools ===============================================
// return pid & new player flag
    function determinePID(address _addr)
        private
        returns(uint256, bool)
    {
        uint256 _pid = pIDxAddr_[_addr];
        if(_pid == 0)
        {
            pID_++;
            pIDxAddr_[_addr] = pID_;
            plyr_[pID_].addr = _addr;

            return (pID_, true);
        } else {
            return (_pid, false);
        }
    }

// external calls =====================================
    function getPlayerID(address _addr)
        isRegisteredGame()
        external
        returns (uint256)
    {
        (uint256 _pid, ) = determinePID(_addr);
        return _pid;
    }

    function getPlayerName(uint256 _pID)
        external
        view
        returns(bytes32)
    {
        return plyr_[_pID].name;
    }

    function getPlayerLAff(uint256 _pID)
        external
        view
        returns(uint256)
    {
        return plyr_[_pID].laff;
    }

    function getPlayerAddr(uint256 _pID)
        external
        view
        returns(address)
    {
        return plyr_[_pID].addr;
    }

    function getNameFee()
        external
        view
        returns(uint256)
    {
        return registrationFee_;
    }

    function registerNameXIDFromDapp(address _addr, bytes32 _name, uint256 _affCode, bool _all)
        isRegisteredGame()
        external
        payable
        returns(bool, uint256)
    {
        // make sure name fees paid
        require(msg.value >= registrationFee_, "you have to pay the name fee");

        // determine if player is new or not
        (uint256 _pID, bool _isNewPlayer) = determinePID(_addr);

        // manage affiliate residuals
        // if no affiliate code was given, no new affiliate code was given, or the 
        // player tried to use their own pID as an affiliate code, lolz
        uint256 _affID = _affCode;
        if(_affID != 0 && _affID != plyr_[_pID].laff && _affID != _pID)
        {
            // update last affiliate 
            plyr_[_pID].laff = _affID;
        } else if(_affID == _pID) {
            _affID = 0;
        }

        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all);

        return (_isNewPlayer, _affID);
    }

    function registerNameXaddrFromDapp(address _addr, bytes32 _name, address _affCode, bool _all)
        isRegisteredGame()
        external
        payable
        returns(bool, uint256)
    {
        // make sure name fees paid
        require(msg.value >= registrationFee_, "you have to pay the name fee");

        // determine if player is new or not
        (uint256 _pID, bool _isNewPlayer) = determinePID(_addr);

        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        uint256 _affID;
        if(_affCode != address(0) && _affCode != _addr)
        {
            // get affiliate ID from aff Code 
            _affID = pIDxAddr_[_affCode];
            
            // if affID is not the same as previously stored 
            if(_affID != plyr_[_pID].laff)
            {
                // update last affiliate
                plyr_[_pID].laff = _affID;
            }
        }

        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all);
        
        return (_isNewPlayer, _affID);
    }

    function registerNameXnameFromDapp(address _addr, bytes32 _name, bytes32 _affCode, bool _all)
        isRegisteredGame()
        external
        payable
        returns(bool, uint256)
    {
        // make sure name fees paid
        require(msg.value >= registrationFee_, "you have to pay the name fee");

        // determine if player is new or not
        (uint256 _pID, bool _isNewPlayer) = determinePID(_addr);

        // manage affiliate residuals
        // if no affiliate code was given or player tried to use their own, lolz
        uint256 _affID;
        if(_affCode != "" && _affCode != _name)
        {
            // get affiliate ID from aff Code 
            _affID = pIDxName_[_affCode];
            
            // if affID is not the same as previously stored 
            if(_affID != plyr_[_pID].laff)
            {
                // update last affiliate
                plyr_[_pID].laff = _affID;
            }
        }

        // register name 
        registerNameCore(_pID, _addr, _affID, _name, _isNewPlayer, _all);

        return(_isNewPlayer, _affID);
    }

// setup ==================================
    function addGame(address _gameAddress, string _gameNameStr)
        onlyOwner()
        public
    {
        require(gameIDs_[_gameAddress] == 0, "that games already been registered");

        gID_++;
        bytes32 _name = _gameNameStr.nameFilter();
        gameIDs_[_gameAddress] = gID_;
        gameNames_[_gameAddress] = _name;
        games_[gID_] = PlayerBookReceiverInterface(_gameAddress);

        games_[gID_].receivePlayerInfo(1, plyr_[1].addr, plyr_[1].name);
    }

    function setRegistrationFee(uint256 _fee)
        onlyOwner()
        public
    {
        registrationFee_ = _fee;
    }
}
