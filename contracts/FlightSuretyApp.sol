pragma solidity ^0.4.25;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    FlightSuretyData flightSuretyData; // Data Instance

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codes
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    // Fee to be paid to be verified(be able to participate)
    uint256 public constant AIRLINE_VERIFICATION_FEE = 10 ether;

    uint256 public constant MAXIMUM_INSURANCE_FEE = 1 ether;

    uint constant M = 4; // Number of keys required for transactions

    bool private operational = true;

    address private contractOwner;          // Account used to deploy contract

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
    }

    mapping(bytes32 => Flight) private flights;


    /********************************************************************************************/
    /*                                       EVENTS                                             */
    /********************************************************************************************/
    event RegisteredAirline(address account);
    event PurchasedInsurance(address airline, address buyer, uint256 amount);
    event CreditedInsuree(address airline, address passenger, uint256 credit);
    event VerifiedAirline(address airline);
    event Withdrawal(address sender, uint256 amount);
    event SubmittedOracleResponse(uint8 indexes, address airline, string flight, uint256 timestamp, uint8 statusCode);

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
    * @dev Modifier that requires the "operational" boolean variable to be "true"
    *      This is used on all state changing functions to pause the contract in
    *      the event there is an issue that needs to be fixed
    */
    modifier requireIsOperational()
    {
        // Modify to call data contract's status
        require(true, "Contract is currently not operational");
        _;
        // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
    * @dev Modifier that requires the "ContractOwner" account to be the function caller
    */
    modifier requireContractOwner()
    {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
    * @dev Contract constructor
    *
    */
    constructor
    (
        address dataContractAddress
    )
    public
    {
        contractOwner = msg.sender;
        flightSuretyData = FlightSuretyData(dataContractAddress);

        // First airline is registered when contract is deployed.
        flightSuretyData.registerAirline(contractOwner, true);
        emit RegisteredAirline(contractOwner);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational()
    public
    view
    returns (bool)
    {
        return operational;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/


    /**
     * @dev Add an airline to the registration queue
     *
     */
    function registerAirline
    (
        address airline
    )
    external
    requireIsOperational
    returns (bool, bool)
    {
        require(airline != address(0), "Invalid address");
        require(flightSuretyData.isAirline(msg.sender), "Only existing airline may register a new airline");
        require(!flightSuretyData.isAirline(airline), "Airline has already been registered");

        uint256 total = flightSuretyData.registeredAirlinesCount();

        if (total < M) {
            flightSuretyData.registerAirline(airline, true);
            return flightSuretyData.getAirline(airline);
        }


        if (flightSuretyData.getVotes(airline) < 1) {
            flightSuretyData.registerAirline(airline, false);
        }

        if (airline != msg.sender) {// You can only vote another airline, not yourself
            uint256 votes = flightSuretyData.voteAirline(airline, msg.sender);

            if (votes >= total / 2) {// 50% consensus
                flightSuretyData.approveAirline(airline);
                emit RegisteredAirline(airline);
            }
        }

        return flightSuretyData.getAirline(airline);
    }

    function verifyAirline() external requireIsOperational payable {
        require(flightSuretyData.isAirline(msg.sender), "You are not registered yet");
        require(!flightSuretyData.isVerified(msg.sender), "You have already been verified");
        require(msg.value >= AIRLINE_VERIFICATION_FEE, "Verification fee is required");

        flightSuretyData.setAirlineVerifiedStatus(msg.sender, true);
        flightSuretyData.creditAirline(msg.sender, AIRLINE_VERIFICATION_FEE);

        // returns change
        if (msg.value > AIRLINE_VERIFICATION_FEE) {
            msg.sender.transfer(msg.value - AIRLINE_VERIFICATION_FEE);
        }

        emit VerifiedAirline(msg.sender);
    }

    function airlineCanParticipate(address airline) external returns (bool) {
        return flightSuretyData.isVerified(airline);
    }

    function hasInsurance(address airline, address passenger) external returns (bool) {
        return flightSuretyData.hasInsurance(airline, passenger);
    }

    // Insurance
    function buyInsurance(address airline) external payable {
        require(this.airlineCanParticipate(airline), "You can't buy insurance for this airline yet");
        require(!this.hasInsurance(airline, msg.sender), "You already have an insurance with this airline");
        require(msg.value > 0, "Insurance fee is required");

        uint256 amount = msg.value;

        if (amount > MAXIMUM_INSURANCE_FEE) {// peg the amount that can be paid to 1 ether
            amount = MAXIMUM_INSURANCE_FEE;
        }

        flightSuretyData.registerInsurance(airline, msg.sender, amount);
        flightSuretyData.creditAirline(airline, amount);

        // returns change
        msg.sender.transfer(msg.value - amount);

        emit PurchasedInsurance(airline, msg.sender, amount);
    }

    function getAirlineBalance(address airline) external view returns (uint256) {
        return flightSuretyData.getAirlineFunds(airline);
    }

    function myBalance(address passenger) external view returns (uint256) {
        return flightSuretyData.getPassengerBalance(passenger);
    }

    function withdraw(uint256 amount) external payable {
        require(this.myBalance(msg.sender) >= amount, "Insufficient balance");

        flightSuretyData.debitPassenger(msg.sender, amount);

        msg.sender.transfer(amount);
        emit Withdrawal(msg.sender, amount);
    }


    /**
     * @dev Register a future flight for insuring.
     *
     */
    function registerFlight
    (
    )
    external
    pure
    {

    }

    /**
     * @dev Called after oracle has updated flight status
     *
     */
    function processFlightStatus
    (
        address airline,
        string memory flight,
        uint256 timestamp,
        uint8 statusCode
    )
    public
    {
        require(airline != address(0), "Invalid airline");
        require(this.airlineCanParticipate(airline), "Airline not available");

        // Only credit if delay is due to airline fault (airline late and late due to technical)
        if (statusCode == STATUS_CODE_LATE_AIRLINE || statusCode == STATUS_CODE_LATE_TECHNICAL) {

            address[] memory passengers = flightSuretyData.getPassengers(airline);

            for (uint i = 0; i < passengers.length; i++) {
                address passenger = passengers[i];
                uint256 amountPaid = flightSuretyData.getPassengerPayment(airline, passenger);

                uint256 amount = amountPaid.mul(3).div(2);

                // funds allocated to the airline have dried up
                require(this.getAirlineBalance(airline) > amount, "We can not process your withdrawal at this time. Please try again later");

                flightSuretyData.debitAirline(airline, amount);
                flightSuretyData.creditPassenger(passenger, amount);
                emit CreditedInsuree(airline, passenger, amount);
            }
        }
    }


    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus
    (
        address airline,
        string flight,
        uint256 timestamp
    )
    external
    {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        oracleResponses[key] = ResponseInfo({
        requester : msg.sender,
        isOpen : true
        });

        emit OracleRequest(index, airline, flight, timestamp);
    }


    // region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 0;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;


    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester;                              // Account that requested status
        bool isOpen;                                    // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses;          // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response
    event FlightStatusInfo(address airline, string flight, uint256 timestamp, uint8 status);

    event OracleReport(address airline, string flight, uint256 timestamp, uint8 status);

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(uint8 index, address airline, string flight, uint256 timestamp);


    // Register an oracle with the contract
    function registerOracle
    (
    )
    external
    payable
    {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({
        isRegistered : true,
        indexes : indexes
        });
    }

    function getMyIndexes
    (
    )
    view
    external
    returns (uint8[3])
    {
        require(oracles[msg.sender].isRegistered, "Not registered as an oracle");

        return oracles[msg.sender].indexes;
    }




    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse
    (
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    )
    external
    {
        require((oracles[msg.sender].indexes[0] == index) || (oracles[msg.sender].indexes[1] == index) || (oracles[msg.sender].indexes[2] == index), "Index does not match oracle request");


        bytes32 key = keccak256(abi.encodePacked(index, airline, flight, timestamp));
        require(oracleResponses[key].isOpen, "Flight or timestamp do not match oracle request");

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES) {

            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }

        emit SubmittedOracleResponse(index, airline, flight, timestamp, statusCode);
    }


    function getFlightKey
    (
        address airline,
        string flight,
        uint256 timestamp
    )
    pure
    internal
    returns (bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes
    (
        address account
    )
    internal
    returns (uint8[3])
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex
    (
        address account
    )
    internal
    returns (uint8)
    {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(uint256(keccak256(abi.encodePacked(blockhash(block.number - nonce++), account))) % maxValue);

        if (nonce > 250) {
            nonce = 0;
            // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

    // endregion
}


// Interface for the FlightSuretyData Contract
contract FlightSuretyData {
    function registeredAirlinesCount() external returns (uint256);

    function getAirline(address account) external returns (bool registered, bool verified);

    function registerAirline(address account, bool _verified) external;

    function voteAirline(address account, address by) external returns (uint256);

    function approveAirline(address account) external;

    function getVotes(address airline) external returns (uint256);

    function isAirline(address account) external returns (bool);

    function isVerified(address account) external returns (bool);

    function setAirlineVerifiedStatus(address account, bool status) external;

    function creditAirline(address account, uint256 amount) external;

    function debitAirline(address account, uint256 amount) external;

    function registerInsurance(address airline, address passenger, uint256 amount) external;

    function hasInsurance(address airline, address passenger) external returns (bool);

    function getAirlineFunds(address airline) external view returns (uint256);

    function getPassengers(address airline) external view returns (address[]);

    function getPassengerPayment(address airline, address passenger) external view returns (uint256);

    function creditPassenger(address passenger, uint256 amount) external;

    function debitPassenger(address passenger, uint256 amount) external;

    function getPassengerBalance(address passenger) external view returns (uint256);
}
