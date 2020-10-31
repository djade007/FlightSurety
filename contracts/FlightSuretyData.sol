pragma solidity ^0.4.25;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false

    struct Airline {
        bool registered;
        bool verified; // verified is true after the payment of 10 ether
        mapping(address => bool) by;
        uint256 approvalCount; // voting count
        uint256 amount;
        address[] passengers;
    }


    mapping(address => uint256) private authorizedCallers; // store authorized contract callers
    mapping(address => Airline) airlines; // store airlines
    uint256 private registeredCount = 0;

    // airline address => passenger address => amount paid
    mapping(address => mapping(address => uint256)) insurances; // store airline to insurance

    mapping(address => uint256) balances; // for passengers
    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/


    /**
    * @dev Constructor
    *      The deploying account becomes contractOwner
    */
    constructor() public
    {
        contractOwner = msg.sender;
    }

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
        require(operational, "Contract is currently not operational");
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
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
    * @dev Get operating status of contract
    *
    * @return A bool that is the current operating status
    */
    function isOperational()
    public
    view
    returns (bool)
    {
        return operational;
    }


    /**
    * @dev Sets contract operations on/off
    *
    * When operational mode is disabled, all write transactions except for this one will fail
    */
    function setOperatingStatus
    (
        bool mode
    )
    external
    requireContractOwner
    {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    function registeredAirlinesCount() external view returns (uint256) {
        return registeredCount;
    }

    function authorizeCaller
    (
        address contractAddress
    )
    external
    requireContractOwner
    {
        authorizedCallers[contractAddress] = 1;
    }

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function registerAirline
    (
        address account,
        bool _registered
    )
    external
    requireIsOperational
    {
        airlines[account] = Airline({
        registered : _registered,
        verified : false,
        approvalCount : 0,
        amount : 0,
        passengers : new address[](0)
        });

        if (_registered) {
            registeredCount++;
        }
    }

    function voteAirline(address account, address by) external returns (uint256) {
        if (airlines[account].by[by] != true) {
            airlines[account].by[by] = true;
            airlines[account].approvalCount++;
        }
        return airlines[account].approvalCount;
    }

    function getVotes(address account) external view returns (uint256) {
        return airlines[account].approvalCount;
    }

    function approveAirline(address account) external {
        if (airlines[account].registered != true) {
            airlines[account].registered = true;
            registeredCount++;
        }
    }

    function getAirline(address account) external view returns (bool registered, bool verified) {
        registered = airlines[account].registered;
        verified = airlines[account].verified;
    }

    function isAirline
    (
        address account
    )
    external
    view
    requireIsOperational
    returns (bool)
    {
        return airlines[account].registered;
    }

    function setAirlineVerifiedStatus(address account, bool status) external requireIsOperational {
        airlines[account].verified = status;
    }

    function creditAirline(address account, uint256 amount) external requireIsOperational {
        airlines[account].amount = airlines[account].amount.add(amount);
    }

    function debitAirline(address account, uint256 amount) external requireIsOperational {
        airlines[account].amount = airlines[account].amount.sub(amount);
    }

    function isVerified(address account) external view returns (bool) {
        return airlines[account].verified;
    }

    function registerInsurance(address airline, address passenger, uint256 amount) external {
        insurances[airline][passenger] = amount;
        airlines[airline].passengers.push(passenger);
    }

    function hasInsurance(address airline, address passenger) external view returns (bool) {
        return insurances[airline][passenger] > 0;
    }

    function getAirlineFunds(address airline) external requireIsOperational view returns (uint256) {
        return airlines[airline].amount;
    }

    function getPassengerPayment(address airline, address passenger) external requireIsOperational view returns (uint256) {
        return insurances[airline][passenger];
    }

    function getPassengers(address airline) external requireIsOperational view returns (address[]) {
        return airlines[airline].passengers;
    }

    function creditPassenger(address passenger, uint256 amount) external {
        balances[passenger] = balances[passenger].add(amount);
    }

    function debitPassenger(address passenger, uint256 amount) external {
        balances[passenger] = balances[passenger].sub(amount);
    }

    function getPassengerBalance(address passenger) external requireIsOperational view returns (uint256) {
        return balances[passenger];
    }

    /**
     * @dev Buy insurance for a flight
     *
     */
    function buy
    (
    )
    external
    payable
    {

    }

    /**
     *  @dev Credits payouts to insurees
    */
    function creditInsurees
    (
    )
    external
    pure
    {
    }


    /**
     *  @dev Transfers eligible payout funds to insuree
     *
    */
    function pay
    (
    )
    external
    pure
    {
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */
    function fund
    (
    )
    public
    payable
    {
    }

    function getFlightKey
    (
        address airline,
        string memory flight,
        uint256 timestamp
    )
    pure
    internal
    returns (bytes32)
    {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    /**
    * @dev Fallback function for funding smart contract.
    *
    */
    function()
    external
    payable
    {
        fund();
    }


}

