const Test = require('../config/testConfig.js');
const BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {
    const M = 4;
    let config;

    before('setup contract', async () => {
        config = await Test.Config(accounts);
        await config.flightSuretyData.authorizeCaller(config.flightSuretyApp.address);
    });

    /****************************************************************************************/
    /* Operations and Settings                                                              */
    /****************************************************************************************/

    it(`(multiparty) has correct initial isOperational() value`, async function () {

        // Get operating status
        let status = await config.flightSuretyData.isOperational.call();
        assert.equal(status, true, "Incorrect initial operating status value");

    });

    it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

        // Ensure that access is denied for non-Contract Owner account
        let accessDenied = false;
        try {
            await config.flightSuretyData.setOperatingStatus(false, {from: config.testAddresses[2]});
        } catch (e) {
            accessDenied = true;
        }
        assert.equal(accessDenied, true, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

        // Ensure that access is allowed for Contract Owner account
        let accessDenied = false;
        try {
            await config.flightSuretyData.setOperatingStatus(false);
        } catch (e) {
            accessDenied = true;
        }
        assert.equal(accessDenied, false, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

        await config.flightSuretyData.setOperatingStatus(false);

        let reverted = false;
        try {
            await config.flightSurety.setTestingMode(true);
        } catch (e) {
            reverted = true;
        }
        assert.equal(reverted, true, "Access not blocked for requireIsOperational");

        // Set it back for other tests to work
        await config.flightSuretyData.setOperatingStatus(true);

    });


    it('(airline) Only existing airline may register a new airline until there are at least four airlines registered', async () => {
        let airlines = [config.airlines[0]];

        for (let i = 1; i < M; i++) { // can register 3 more airlines in addition to the first one
            let airline = config.airlines[i];
            let previousAirline = config.airlines[i - 1];
            await config.flightSuretyApp.registerAirline(airline, {from: previousAirline});
            let isAirline = await config.flightSuretyData.isAirline.call(airline);
            assert.equal(isAirline, true);
            airlines.push(airline);
        }

        assert.equal(airlines.length, M);
    });

    it('(airline) Registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines', async () => {
        let fifthAirline = config.airlines[4];

        await config.flightSuretyApp.registerAirline(fifthAirline, {from: config.airlines[0]});
        let isAirline = await config.flightSuretyData.isAirline.call(fifthAirline);
        // not approved yet. Atleast (50% of M) votes is needed
        assert.equal(isAirline, false);


        // 1 more airline can vote to register the airline
        const min = Math.ceil(M / 2); // 2
        for (let i = 1; i < min; i++) { // run once
            await config.flightSuretyApp.registerAirline(fifthAirline, {from: config.airlines[i]});
        }

        // 50% has been reached
        isAirline = await config.flightSuretyData.isAirline.call(fifthAirline);
        assert.equal(isAirline, true);
    });

    it('(airline) Airline can be registered, but does not participate in contract until it submits funding of 10 ether', async () => {
        let canParticipate = await config.flightSuretyApp.airlineCanParticipate.call(config.airlines[1]);
        assert.equal(canParticipate, false);

        // fund
        await config.flightSuretyApp.verifyAirline({from: config.airlines[1], value: web3.utils.toWei("20", "ether")});

        canParticipate = await config.flightSuretyApp.airlineCanParticipate.call(config.airlines[1]);
        assert.equal(canParticipate, true);
    });

    it('(passengers) Passengers may pay up to 1 ether for purchasing flight insurance', async () => {
        let passenger = accounts[9];
        let airline = config.airlines[1];
        let amount = web3.utils.toWei("1", "ether");

        let hasInsurance = await config.flightSuretyApp.hasInsurance.call(airline, passenger);
        assert.equal(hasInsurance, false);

        let initialBalance = await config.flightSuretyApp.getAirlineBalance.call(airline);

        try {
            await config.flightSuretyApp.buyInsurance(airline, {from: passenger, value: amount});
        } catch (e) {
            console.log(e);
        }

        hasInsurance = await config.flightSuretyApp.hasInsurance.call(airline, passenger);
        assert.equal(hasInsurance, true);

        let finalBalance = await config.flightSuretyApp.getAirlineBalance.call(airline);

        assert.equal(BigNumber.sum(initialBalance, amount).isEqualTo(finalBalance), true);
    });

    it('(passengers) If flight is delayed due to airline fault, passenger receives credit of 1.5X the amount they paid', async () => {
        let passenger = accounts[9];
        let paid = web3.utils.toWei("1", "ether");

        let flight = 'FLT01';
        let STATUS_CODE_LATE_AIRLINE = 20;
        let airline = config.airlines[1];
        let timestamp = Math.floor(Date.now() / 1000);

        let initialBalance = await config.flightSuretyApp.myBalance.call(passenger);

        await config.flightSuretyApp.processFlightStatus(airline, flight, timestamp, STATUS_CODE_LATE_AIRLINE);

        let finalBalance = await config.flightSuretyApp.myBalance.call(passenger);

        let fee = new BigNumber(paid).multipliedBy(3).dividedBy(2);
        assert.equal(BigNumber.sum(initialBalance, fee).isEqualTo(finalBalance), true);
    });

    it('(passengers) Passenger can withdraw any funds owed to them as a result of receiving credit for insurance payout', async () => {
        let passenger = accounts[9];
        let amount = web3.utils.toWei("1", "ether");

        let initialBalance = await config.flightSuretyApp.myBalance.call(passenger);

        try {
            await config.flightSuretyApp.withdraw(amount, {from: passenger});
        } catch (e) {
            console.log(e);
        }

        let finalBalance = await config.flightSuretyApp.myBalance.call(passenger);

        assert.equal(BigNumber.sum(initialBalance, -amount).isEqualTo(finalBalance), true);
    });
});
