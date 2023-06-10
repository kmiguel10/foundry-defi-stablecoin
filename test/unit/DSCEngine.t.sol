//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {console} from "forge-std/console.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    address public NOT_OWNER_USER = makeAddr("not owner");
    address public LIQUIDATOR = makeAddr("liquidator");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ETHER_BALANCE = 10 ether;
    uint256 public constant AMOUNT_MINT = 100 ether; //this gives a health factor 100000000000000000e18
    uint256 public constant COLLATERAL_TO_COVER = 20 ether;

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ETHER_BALANCE);
    }

    ////////////////////////
    //   Constructor Test //
    ///////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //////////////////
    //   Price Test //
    /////////////////

    function testGetUsdValue() public {
        uint256 ethAmount = 15e18;
        //15e18 * 2000 eth  = 30,000e18
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function getTokenAmountFromUsd() public {
        uint256 usdAmount = 100 ether;
        // $2000 / ETH, $100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(actualWeth, expectedWeth);
    }

    //////////////////////////////
    //   Deposit Collateral Test //
    ///////////////////////////////
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(weth, 0); //this should revert
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        //Create a random token
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount);
    }

    function testGetAccountCollateralValue() public depositCollateral {
        uint256 _userCollateralValue = dsce.getAccountCollateralValue(USER);
        uint256 _expectedCollateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(_expectedCollateralValue, _userCollateralValue);
    }

    function testCollateralEventEmittedAfterDeposit() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectEmit(true, true, true, false);
        emit CollateralDeposited(USER, weth, AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    ///////////////////////////////
    //   Mint Collateral Test    //
    ///////////////////////////////

    //Can I mint before depositing collateral?
    // Need to deposit collateral first before minting...
    function testRevertIfMintAmountIsZero() public {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
    }

    //Should revert because user didnt deposit collateral
    function testRevertIfAttemptToMintWithoutCollateral() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        dsce.mintDsc(100);
        vm.stopPrank();
    }

    //2 tests:
    //1. Deposit collateral and break healthfactor
    //2. Emit minted event

    function testRevertBrokenHealthHealthFactorWithCollateral() public depositCollateral {
        //need to break healthfactor
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 10000000000000));
        dsce.mintDsc(1000000000000000000000000000);
        vm.stopPrank();
    }

    function testEmitAfterMinting() public depositCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), USER, 100000);
        dsce.mintDsc(100000);
        // console.log("Health factor after mint", dsce.getHealthFactor(USER));
        vm.stopPrank();
    }

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);

        assertEq(userBalance, AMOUNT_MINT);
    }

    ///////////////////////////////////////
    //   Burn / Redeem Collateral Test    //
    ////////////////////////////////////////
    //test functions:
    // redeemCollateral
    // burnDsc
    // - emit burn event
    //NOTE: Need to create Mock files for failed tests

    modifier mintDse() {
        vm.startPrank(USER);
        dsce.mintDsc(5555500000000000000000);
        vm.stopPrank();
        _;
    }

    function testRevertIfBurnAmountIsZero() public depositCollateral mintDse {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.burnDsc(0);
    }

    function testRevertIfBurnWithoutMinting() public depositCollateral {
        vm.expectRevert(DSCEngine.DSCEngine__UserHasNoMintedCoinsToBurn.selector);
        dsce.burnDsc(100);
    }

    function testEmitBurnEventAfterBurn() public depositCollateral mintDse {
        vm.startPrank(USER);
        //Me as the user (owner) must approve the engine to receive dsc
        dsc.approve(address(dsce), 1);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(dsce), address(0), 1);
        dsce.burnDsc(1);
        vm.stopPrank();
    }

    function testRevertRedeemCollateralAmountZero() public depositCollateral mintDse {
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
    }

    /**
     * @dev there was  a bug in _healthFactor where after burning... it is dividing by zero which throws an error
     */
    function testRedeemCollateralForDsc() public {
        //approve dsce for weth transfer
        //call deposit collateral and mint
        //approve dsce for dsc
        //call redeemcollareralforDsc

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        console.log("User minted", dsc.balanceOf(USER));
        dsc.approve(address(dsce), AMOUNT_MINT);
        dsce.redeemCollateralForDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();

        uint256 userDscBalance = dsc.balanceOf(USER);

        assertEq(userDscBalance, 0);
    }

    /////////////////////////
    //   Liquidate Test    //
    /////////////////////////

    /**
     * Test for:
     *  - zero debt to cover
     *  - healthfactor has to be below 1 to liquidate
     *  - test for BONUS + collateral = totalCollateral to receive by the liquidator
     * - revert IF after liquidator, the liquidator's healthFactor is below 1
     * - Cannot liquidate if healthy
     * - liquidate if healthy
     * - after liquidation user has nom more debt
     *
     */

    /**
     * Create a liquidated modifier
     */
    modifier liquidated() {
        //Create a user with bad health factor
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralAndMintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();

        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dsce.getHealthFactor(USER);
        console.log("User health factor: ", userHealthFactor);

        //Mint weth for liquidator to cover debt
        ERC20Mock(weth).mint(LIQUIDATOR, COLLATERAL_TO_COVER);

        //Liquidator liquidates USER
        vm.startPrank(LIQUIDATOR);
        ERC20Mock(weth).approve(address(dsce), COLLATERAL_TO_COVER);
        dsce.depositCollateralAndMintDsc(weth, COLLATERAL_TO_COVER, AMOUNT_MINT);
        //Liquidator approves dsce to receive dsc
        dsc.approve(address(dsce), AMOUNT_MINT);
        //Liquidator covers entire debt
        dsce.liquidate(weth, USER, AMOUNT_MINT);
        vm.stopPrank();
        _;
    }

    function testLiquidatorTakesOnUsersDebt() public liquidated {
        (uint256 liquidatorDscMinted,) = dsce.getAccountInformation(LIQUIDATOR);
        assertEq(liquidatorDscMinted, AMOUNT_MINT);
    }

    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }
}
