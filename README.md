# utils-contract
Useful solidity contract libraries.

- defi
- proxy
- security
- token 
- math


## defi
### getZapVaule.sol
1. Predict asset value after Token to Token
```
function getValueOfTokenToToken(
    address token, 
    uint amount, 
    address [] memory pathArr
) external view returns (uint inputVaule, uint outputValue)
```

Parameters:
- token: Enter the token address. If it is coin, enter the WBNB address.
- amount: Numbers of tokens.
- pathArr: An array of address sets. The default array begins with the token address passed in and ends with the token address specified for output.

Return:
- inputVaule: The actual asset value of the token passed in.
- outputValue: Forecast the value of assets after Zap conversion.

2. Predict asset value after Token to Lp
```
function getValueOfTokenToLp(
    address token, 
    uint amount, 
    address [] memory pathArr0,
    address [] memory pathArr1
) external view returns (uint inputVaule, uint outputValue)
```

Parameters:
- token: Enter the token address. If it is coin, enter the WBNB address.
- amount: Numbers of tokens.
- pathArr0: An array of address sets representing the conversion of the passed token to the specified output token. If the passed token is the same address as the specified output token, this parameter is represented by an empty array `[]`.

- pathArr1: An array of address sets representing the conversion of the passed token to the specified output token. If the passed token is the same address as the specified output token, this parameter is represented by an empty array `[]`.

Return:
- inputVaule: The actual asset value of the token passed in.
- outputValue: Forecast the value of assets after Zap conversion.