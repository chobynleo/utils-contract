//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "../interfaces/IPair.sol";
import "../interfaces/IUSDOracle.sol";
import "../interfaces/IRouter02.sol";
import "../interfaces/IPancakeFactory.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract getZapValue{

  using SafeMath for uint;

  IUSDOracle private oracle;
  IPancakeFactory private factory;
  IRouter02 private router;
  
  address public minter;

  constructor(address _oracle, address _factory, address _router) {
    oracle = IUSDOracle(_oracle);
    factory = IPancakeFactory(_factory);
    router = IRouter02(_router);
  }

  function getValueOfTokenToLp(
        address token, 
        uint amount, 
        address [] memory pathArr0,
        address [] memory pathArr1
    ) external view returns(uint inputVaule, uint outputValue) {
        {
          uint scale = 10 ** IERC20Metadata(token).decimals();
          inputVaule = oracle.getPrice(token) * amount / scale;
        }
        
        address token0;
        address token1;
        uint amountOut0;
        uint amountOut1;
        uint112[] memory reserves = new uint112[](2);

        {
          address lp;
          // get token reserves before swapping
          (reserves, lp) = _getReserves(token, pathArr0, pathArr1);

          (token0, amountOut0, reserves) = _predictSwapAmount(token, amount / 2, pathArr0, reserves, lp);
          (token1, amountOut1, reserves) = _predictSwapAmount(token, amount - amount / 2, pathArr1, reserves, lp);
        }
        _checkAmountOut(token0, token1, amountOut0, amountOut1);

        (uint actualAmountOut0, uint actualAmountOut01) = _getQuoteAmount(token0, amountOut0, token1, amountOut1, reserves);

        uint price0 = _getPrice(token, pathArr0);
        uint price1 = _getPrice(token, pathArr1);

        uint scale0 = 10 ** IERC20Metadata(token0).decimals();
        uint scale1 = 10 ** IERC20Metadata(token1).decimals();

        outputValue = actualAmountOut0 * price0 / scale0 + actualAmountOut01 * price1 / scale1;
    }

    function getValueOfTokenToToken(
        address token, 
        uint amount, 
        address [] memory pathArr
    ) external view returns(uint inputVaule, uint outputValue) {
        uint scaleIn = 10 ** IERC20Metadata(token).decimals();
        inputVaule = oracle.getPrice(token) * amount / scaleIn;

        address targetToken;
        uint amountOut;
        uint112[] memory reserves = new uint112[](2);

        (targetToken, amountOut, reserves) = _predictSwapAmount(token, amount, pathArr, reserves, address(0));

        uint price = _getPrice(token, pathArr);

        uint scaleOut = 10 ** IERC20Metadata(targetToken).decimals();

        outputValue = amountOut * price / scaleOut;
    }

    function _predictSwapAmount(
        address originToken,
        uint amount, 
        address [] memory pathArr,
        uint112 [] memory reserves,
        address lp
    ) internal view returns (address targetToken, uint amountOut, uint112 [] memory _reserves) {
        if (pathArr.length == 0) {
              return (originToken, amount, reserves);
        }

        (amountOut, _reserves) = _getAmountOut(amount, pathArr, reserves, lp);
        return (pathArr[pathArr.length - 1], amountOut, _reserves);
    }

    function _fillArrbyPosition(
        uint start,
        uint end,
        address[] memory originArr
    ) internal view returns (address[] memory) {
        uint newLen = end-start+1;
        address[] memory newArr = new address[](newLen);
        for (uint i = 0; i < newLen; i++) {
            newArr[i] = originArr[i+start];
        }
        return newArr;
    }

    function _getAmountOut(
      uint amount, 
      address[] memory path,
      uint112 [] memory reserves,
      address lp
      ) internal view returns (uint amountOut, uint112 [] memory){
  
        if(lp != address(0)){
          // swap Token to Lp. 
          IPair pair = IPair(lp);
          address token0 = pair.token0();
          address token1 = pair.token1();
          uint slow = 0;
          uint fast = 1;
          uint start = 0; // currently start to swap

          amountOut = amount;

          for (fast; fast < path.length; fast++) {
            if(path[slow] == token0 && path[fast] == token1) {
              // token0 -> token1
              if(start < slow) {
                // ... -> token0, token0 -> token1
                address[] memory newPathArr = _fillArrbyPosition(start, slow, path);
                amountOut = _tryToGetAmountsOut(amountOut, newPathArr);
                uint token0GapAmount = amountOut;
                amountOut = _getAmountsOutByReserves(token0GapAmount, uint(reserves[0]), uint(reserves[1]));
                uint token1GapAmount = amountOut;
                reserves[0] += uint112(token0GapAmount);
                reserves[1] -= uint112(token1GapAmount);
              } else {
                // start = slow, means token0 -> token1
                uint token0GapAmount = amountOut;
                amountOut = _getAmountsOutByReserves(token0GapAmount, uint(reserves[0]), uint(reserves[1]));
                uint token1GapAmount = amountOut;
                reserves[0] += uint112(token0GapAmount);
                reserves[1] -= uint112(token1GapAmount);
              }
              // reassignment
              start = fast;
            } else if(path[slow] == token1 && path[fast] == token0) {
              // token1 -> token0
              if(start < slow) {
                // ... -> token1, token1 -> token0
                address[] memory newPathArr = _fillArrbyPosition(start, slow, path);
                amountOut = _tryToGetAmountsOut(amountOut, newPathArr);
                uint token1GapAmount = amountOut;
                amountOut = _getAmountsOutByReserves(token1GapAmount, uint(reserves[1]), uint(reserves[0]));
                uint token0GapAmount = amountOut;
                reserves[1] += uint112(token1GapAmount);
                reserves[0] -= uint112(token0GapAmount);
              } else {
                // start = slow, means token1 -> token0
                uint token1GapAmount = amountOut;
                amountOut = _getAmountsOutByReserves(token1GapAmount, uint(reserves[1]), uint(reserves[0]));
                uint token0GapAmount = amountOut;
                reserves[1] += uint112(token1GapAmount);
                reserves[0] -= uint112(token0GapAmount);
              }
              // reassignment
              start = fast;
            } else {
              if(fast == path.length - 1) {
                // path end
                address[] memory newPathArr = _fillArrbyPosition(start, fast, path);
                amountOut = _tryToGetAmountsOut(amountOut, newPathArr);
              }
            }
            slow++;
          }

        } else {
          // swap Token to Token
          amountOut = _tryToGetAmountsOut(amount, path);
        }
        return(amountOut, reserves);
    }

    function _tryToGetAmountsOut(
      uint amount, 
      address[] memory path
    ) internal view returns(uint amountOut) {
      try router.getAmountsOut(amount, path) returns (uint[] memory amounts) {
        amountOut = amounts[amounts.length - 1];
      } catch {
        revert("Wrong Path");
      }
    }

    function _getAmountsOutByReserves(
      uint amountIn, 
      uint reserveIn, 
      uint reserveOut
    ) internal view returns(uint amountOut) {
      require(amountIn > 0, 'Reader: INSUFFICIENT_INPUT_AMOUNT');
      require(reserveIn > 0 && reserveOut > 0, 'Reader: INSUFFICIENT_LIQUIDITY');
      uint amountInWithFee = amountIn.mul(9975);
      uint numerator = amountInWithFee.mul(reserveOut);
      uint denominator = reserveIn.mul(10000).add(amountInWithFee);
      amountOut = numerator / denominator;
    }

    function _getPrice(
        address token,
        address[] memory pathArr
    ) internal view returns (uint price) {
        if (pathArr.length == 0) {
            // tokenInput 
            return oracle.getPrice(token);
        }
        // tokenOutput
        address _token = pathArr[pathArr.length - 1];
        price = oracle.getPrice(_token);
    }

    function _getQuoteAmount(
        address token0,
        uint amountOut0,
        address token1,
        uint amountOut1,
        uint112[] memory reserves
    ) internal view returns (uint actualAmountOut0, uint actualAmountOut1) {
        address lp = factory.getPair(token0, token1);
        IPair pair = IPair(lp);
        address _token0 = pair.token0();
        address _token1 = pair.token1();

        uint112 reserve0 = reserves[0];
        uint112 reserve1 = reserves[1];
        
        if(_token0 != token0) {
          // switch places when not match
          uint112 temp = reserve0;
          reserve0 = reserve1;
          reserve1 = temp;
        }

        uint quoteAmountOut1 = router.quote(amountOut0, reserve0, reserve1);
        uint quoteAmountOut0 = router.quote(amountOut1, reserve1, reserve0);

        if(quoteAmountOut1 <= amountOut1) {
          return(amountOut0, quoteAmountOut1);
        } else if(quoteAmountOut0 <= amountOut0) {
          return(quoteAmountOut0, amountOut1);
        } else {
          revert("Reader: predict addLiquidity error");
        }
    }

    function _checkAmountOut(
        address token0,
        address token1,
        uint amountOut0,
        uint amountOut1
    ) internal view {
        address lp = factory.getPair(token0, token1);
        IPair pair = IPair(lp);
        address _token0 = pair.token0();
        address _token1 = pair.token1();

        require(amountOut0 > 0 && amountOut1 > 0, "Wrong Path: amountOut is zero");
        require(token0 == _token0 || token0 == _token1, "Wrong Path: target tokens don't match");
        require(token1 == _token0 || token1 == _token1, "Wrong Path: target tokens don't match");
    }

    function _getReserves(
        address token,
        address[] memory pathArr0,
        address[] memory pathArr1
    ) internal view returns(uint112[] memory, address lp){
        address token0 = pathArr0.length == 0? token: pathArr0[pathArr0.length - 1];
        address token1 = pathArr1.length == 0? token: pathArr1[pathArr1.length - 1];

        require(token0 != token1, "Zap: target tokens should't be the same");

        lp = factory.getPair(token0, token1);
        IPair pair = IPair(lp);

        uint112[] memory _reserves = new uint112[](2);
        (_reserves[0], _reserves[1], ) = pair.getReserves();
        return (_reserves, lp);
    }
}
