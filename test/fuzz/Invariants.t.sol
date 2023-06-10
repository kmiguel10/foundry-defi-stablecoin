//SPDX-License-Identifier: MIT

//Have our invariants aka properties

//What are our invariants?
//1. The total supply of dsc (debt) should be less than the total value of collateral
//Getter view function should never revert <- evergreen invariant

//the fail_on_revert = true in toml file means that the fuzzer will call random functions ... which will always fail....the idea of the Handler is to route/guide the fuzzer into calling function randomly in a more meaningful way....

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        //get the value of all the collateral in the protocol
        //compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce)); //total weth deposited into dsce
        uint256 totalBtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalBtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("totalSupply value: ", totalSupply);
        console.log("Times mint called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    /**
     * This function tests all the getters, if this fails then there is something wring with the invariants...none of this should fail and it is any east test
     */
    function invariant_getterShouldNotRevert() public view {
        dsce.getCollateralTokens();
        //dsce.getCollateralBalanceOfUser();
    }
}
