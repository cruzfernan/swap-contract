%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_check,
    uint256_sqrt,
    uint256_le,
    uint256_lt,
)
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.math_cmp import is_le_felt
from starkware.cairo.common.math import assert_nn, assert_not_equal, assert_not_zero
from starkware.cairo.common.bitwise import bitwise_or, bitwise_and
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)

from openzeppelin.security.reentrancyguard import ReentrancyGuard
from openzeppelin.security.safemath import SafeUint256
from openzeppelin.token.erc20.library import ERC20, ERC20_total_supply, ERC20_balances, Transfer
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20

from warplib.maths.div import warp_div256
from warplib.maths.mul import warp_mul256
from warplib.maths.mod import warp_mod
from warplib.maths.gt import warp_gt
from warplib.maths.neq import warp_neq
from warplib.maths.add import warp_add256
from warplib.maths.int_conversions import warp_int256_to_int112, warp_int128_to_int32

from libraries.helper import min_uint256
from libraries.uq112x112 import Q112, encode, uqdiv

#
# ERC20 === start ===
#

@view
func name{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (name : felt):
    let (name) = ERC20.name()
    return (name)
end

@view
func symbol{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (symbol : felt):
    let (symbol) = ERC20.symbol()
    return (symbol)
end

@view
func totalSupply{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    totalSupply : Uint256
):
    let (totalSupply) = ERC20.total_supply()
    return (totalSupply)
end

@view
func decimals{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    decimals : felt
):
    let (decimals) = ERC20.decimals()
    return (decimals)
end

@view
func balanceOf{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt
) -> (balance : Uint256):
    let (balance) = ERC20.balance_of(account)
    return (balance)
end

@view
func allowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    owner : felt, spender : felt
) -> (remaining : Uint256):
    let (remaining) = ERC20.allowance(owner, spender)
    return (remaining)
end

@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient : felt, amount : Uint256
) -> (success : felt):
    ERC20.transfer(recipient, amount)
    return (TRUE)
end

@external
func transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender : felt, recipient : felt, amount : Uint256
) -> (success : felt):
    ERC20.transfer_from(sender, recipient, amount)
    return (TRUE)
end

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, amount : Uint256
) -> (success : felt):
    ERC20.approve(spender, amount)
    return (TRUE)
end

@external
func increaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, added_value : Uint256
) -> (success : felt):
    ERC20.increase_allowance(spender, added_value)
    return (TRUE)
end

@external
func decreaseAllowance{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, subtracted_value : Uint256
) -> (success : felt):
    ERC20.decrease_allowance(spender, subtracted_value)
    return (TRUE)
end

#
# ERC20 === end ===
#

#
# Pair === start ===
#

#
# Constants
#

# Cairo supports defining constant expressions (only integers(felt))
# https://www.cairo-lang.org/docs/how_cairo_works/consts.html
const _MINIMUM_LIQUIDITY = 10 ** 3

#
# Events
#

@event
func Mint(sender : felt, amount0 : Uint256, amount1 : Uint256):
end

@event
func Burn(sender : felt, amount0 : Uint256, amount1 : Uint256, to : felt):
end

@event
func Swap(
    sender : felt,
    amount0In : Uint256,
    amount1In : Uint256,
    amount0Out : Uint256,
    amount1Out : Uint256,
    to : felt,
):
end

@event
func Sync(reserve0 : felt, reserve1 : felt):
end

#
# Storage
#

@storage_var
func _factory() -> (factory : felt):
end

@storage_var
func _token0() -> (token0 : felt):
end

@storage_var
func _token1() -> (token1 : felt):
end

# Type: uint112
@storage_var
func _reserve0() -> (reserve0 : felt):
end

@storage_var
func _reserve1() -> (reserve1 : felt):
end

@storage_var
func _blockTimestampLast() -> (blockTimestampLast : felt):
end

@storage_var
func _price0CumulativeLast() -> (price0CumulativeLast : Uint256):
end

@storage_var
func _price1CumulativeLast() -> (price1CumulativeLast : Uint256):
end

# reserve0 * reserve1, as of immediately after the most recent liquidity event
@storage_var
func _kLast() -> (kLast : Uint256):
end

#
# Constructor
#

@constructor
func constructor{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    let (sender) = get_caller_address()
    _factory.write(sender)
    return ()
end

#
# Getters
#

@view
func MINIMUM_LIQUIDITY{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    MINIMUM_LIQUIDITY : felt
):
    return (MINIMUM_LIQUIDITY=_MINIMUM_LIQUIDITY)
end

@view
func factory{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    factory : felt
):
    let (value) = _factory.read()
    return (factory=value)
end

@view
func token0{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (token0 : felt):
    let (value) = _token0.read()
    return (token0=value)
end

@view
func token1{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (token1 : felt):
    let (value) = _token1.read()
    return (token1=value)
end

@view
func blockTimestampLast{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    blockTimestampLast : felt
):
    let (value) = _blockTimestampLast.read()
    return (blockTimestampLast=value)
end

@view
func price0CumulativeLast{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    price0CumulativeLast : Uint256
):
    let (value) = _price0CumulativeLast.read()
    return (price0CumulativeLast=value)
end

@view
func price1CumulativeLast{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    price1CumulativeLast : Uint256
):
    let (value) = _price1CumulativeLast.read()
    return (price1CumulativeLast=value)
end

@view
func kLast{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    kLast : Uint256
):
    let (value) = _kLast.read()
    return (kLast=value)
end

#
# Externals
#

# called once by the factory at time of deployment
@external
func initialize{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    token0 : felt, token1 : felt
) -> ():
    let (factory) = _factory.read()
    let (sender) = get_caller_address()
    with_attr error_message("10kSwap: FB"):
        assert factory = sender
    end

    _token0.write(token0)
    _token1.write(token1)

    ERC20.initializer('10kSwap Pair Token', 'LPT', 18)

    return ()
end

@external
func getReserves{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    reserve0 : felt, reserve1 : felt, blockTimestampLast : felt
):
    let (reserve0) = _reserve0.read()
    let (reserve1) = _reserve1.read()
    let (blockTimestampLast) = _blockTimestampLast.read()

    return (reserve0=reserve0, reserve1=reserve1, blockTimestampLast=blockTimestampLast)
end

# this low-level function should be called from a contract which performs important safety checks
@external
func mint{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(to : felt) -> (liquidity : Uint256):
    alloc_locals

    ReentrancyGuard._start()

    let (reserve0, reserve1, _) = getReserves()
    let (token0) = _token0.read()
    let (token1) = _token1.read()
    let (self) = get_contract_address()
    let (balance0 : Uint256) = IERC20.balanceOf(contract_address=token0, account=self)
    let (balance1 : Uint256) = IERC20.balanceOf(contract_address=token1, account=self)
    let (amount0) = SafeUint256.sub_le(balance0, Uint256(low=reserve0, high=0))
    let (amount1) = SafeUint256.sub_le(balance1, Uint256(low=reserve1, high=0))

    # let (feeOn) = _mintFee(reserve0, reserve1)
    let (totalSupply : Uint256) = ERC20.total_supply()

    let (zero_total_supply) = bitwise_or(totalSupply.low, totalSupply.high)  # 0|0=0  0|1=1  1|0=1  1|1=1
    if zero_total_supply == 0:
        let (n) = warp_mul256(amount0, amount1)
        let (sq : Uint256) = uint256_sqrt(n)
        let (_liquidity : Uint256) = SafeUint256.sub_le(sq, Uint256(low=_MINIMUM_LIQUIDITY, high=0))

        # permanently lock the first _MINIMUM_LIQUIDITY tokens
        _mint(0, Uint256(low=_MINIMUM_LIQUIDITY, high=0))

        _mint_part1(to, amount0, amount1, _liquidity, balance0, balance1, reserve0, reserve1)

        ReentrancyGuard._end()
        return (_liquidity)
    else:
        # a = amount0 * totalSupply / reserve0
        # b = amount1 * totalSupply / reserve1
        # liquidity = min(a, b)
        let (a_lhs : Uint256) = warp_mul256(amount0, totalSupply)
        let (a : Uint256) = warp_div256(a_lhs, Uint256(low=reserve0, high=0))
        let (b_lhs : Uint256) = warp_mul256(amount1, totalSupply)
        let (b : Uint256) = warp_div256(b_lhs, Uint256(low=reserve1, high=0))
        let (_liquidity : Uint256) = min_uint256(a, b)

        _mint_part1(to, amount0, amount1, _liquidity, balance0, balance1, reserve0, reserve1)

        ReentrancyGuard._end()
        return (_liquidity)
    end
end

# this low-level function should be called from a contract which performs important safety checks
@external
func burn{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(to : felt) -> (amount0 : Uint256, amount1 : Uint256):
    alloc_locals

    ReentrancyGuard._start()

    let (reserve0, reserve1, _) = getReserves()
    let (token0) = _token0.read()
    let (token1) = _token1.read()
    let (self) = get_contract_address()
    let (balance0 : Uint256) = IERC20.balanceOf(contract_address=token0, account=self)
    let (balance1 : Uint256) = IERC20.balanceOf(contract_address=token1, account=self)
    let (liquidity : Uint256) = ERC20.balance_of(account=self)

    let (feeOn) = _mintFee(reserve0, reserve1)
    let (totalSupply : Uint256) = ERC20.total_supply()

    # using balances ensures pro-rata distribution
    let (a0) = warp_mul256(liquidity, balance0)
    let (amount0) = warp_div256(a0, totalSupply)
    let (a1) = warp_mul256(liquidity, balance1)
    let (amount1) = warp_div256(a1, totalSupply)

    # Insufficient liquidity burned
    with_attr error_message("10kSwap: ILB"):
        let (r0) = uint256_le(amount0, Uint256(low=0, high=0))
        let (r1) = uint256_le(amount1, Uint256(low=0, high=0))
        assert r0 = FALSE
        assert r1 = FALSE
    end

    _burn(self, liquidity)
    IERC20.transfer(contract_address=token0, recipient=to, amount=amount0)
    IERC20.transfer(contract_address=token1, recipient=to, amount=amount1)
    let (balance0 : Uint256) = IERC20.balanceOf(contract_address=token0, account=self)
    let (balance1 : Uint256) = IERC20.balanceOf(contract_address=token1, account=self)
    _update(balance0, balance1, reserve0, reserve1)

    # TODO
    # if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
    let (sender) = get_caller_address()
    Burn.emit(sender, amount0, amount1, to)

    ReentrancyGuard._end()

    return (amount0=amount0, amount1=amount1)
end

# // this low-level function should be called from a contract which performs important safety checks
# function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
#     require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
#     (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
#     require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

# uint balance0;
#     uint balance1;
#     { // scope for _token{0,1}, avoids stack too deep errors
#     address _token0 = token0;
#     address _token1 = token1;
#     require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');
#     if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
#     if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
#     if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
#     balance0 = IERC20(_token0).balanceOf(address(this));
#     balance1 = IERC20(_token1).balanceOf(address(this));
#     }
#     uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
#     uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
#     require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
#     { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
#     uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
#     uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
#     require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
#     }

# _update(balance0, balance1, _reserve0, _reserve1);
#     emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
# }

# this low-level function should be called from a contract which performs important safety checks
@external
func swap{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(amount0Out : Uint256, amount1Out : Uint256, to : felt) -> ():
    alloc_locals

    ReentrancyGuard._start()

    # Insufficient output amount
    with_attr error_message("10kSwap: IOA"):
        # Require amount0Out > 0 || amount1Out > 0
        let (r0) = uint256_le(amount0Out, Uint256(low=0, high=0))
        let (r1) = uint256_le(amount1Out, Uint256(low=0, high=0))
        let (_and) = bitwise_and(r0, r1)
        assert _and = FALSE
    end

    let (reserve0, reserve1, _) = getReserves()

    # Insufficient liquidity
    with_attr error_message("10kSwap: IL"):
        let (r0) = uint256_lt(amount0Out, Uint256(low=reserve0, high=0))
        let (r1) = uint256_lt(amount1Out, Uint256(low=reserve1, high=0))
        let (_and) = bitwise_and(r0, r1)
        assert _and = TRUE
    end

    let (token0) = _token0.read()
    let (token1) = _token1.read()
    let (self) = get_contract_address()
    let (balance0 : Uint256) = IERC20.balanceOf(contract_address=token0, account=self)
    let (balance1 : Uint256) = IERC20.balanceOf(contract_address=token1, account=self)


    let (feeOn) = _mintFee(reserve0, reserve1)
    let (totalSupply : Uint256) = ERC20.total_supply()

    # using balances ensures pro-rata distribution
    let (a0) = warp_mul256(liquidity, balance0)
    let (amount0) = warp_div256(a0, totalSupply)
    let (a1) = warp_mul256(liquidity, balance1)
    let (amount1) = warp_div256(a1, totalSupply)

    # Insufficient liquidity burned
    with_attr error_message("10kSwap: ILB"):
        let (r0) = uint256_le(amount0, Uint256(low=0, high=0))
        let (r1) = uint256_le(amount1, Uint256(low=0, high=0))
        assert r0 = FALSE
        assert r1 = FALSE
    end

    _burn(self, liquidity)
    IERC20.transfer(contract_address=token0, recipient=to, amount=amount0)
    IERC20.transfer(contract_address=token1, recipient=to, amount=amount1)
    let (balance0 : Uint256) = IERC20.balanceOf(contract_address=token0, account=self)
    let (balance1 : Uint256) = IERC20.balanceOf(contract_address=token1, account=self)
    _update(balance0, balance1, reserve0, reserve1)

    # TODO
    # if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
    let (sender) = get_caller_address()
    Burn.emit(sender, amount0, amount1, to)

    ReentrancyGuard._end()

    return (amount0=amount0, amount1=amount1)
end

# force balances to match reserves
@external
func skim{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(to : felt) -> ():
    alloc_locals

    ReentrancyGuard._start()

    let (token0) = _token0.read()
    let (token1) = _token1.read()
    let (self) = get_contract_address()
    let (balance0 : Uint256) = IERC20.balanceOf(contract_address=token0, account=self)
    let (balance1 : Uint256) = IERC20.balanceOf(contract_address=token1, account=self)
    let (reserve0) = _reserve0.read()
    let (reserve1) = _reserve1.read()

    # Todo: To be implemented safeTransfer
    let (diff0) = SafeUint256.sub_le(balance0, Uint256(low=reserve0, high=0))
    let (diff1) = SafeUint256.sub_le(balance1, Uint256(low=reserve1, high=0))
    IERC20.transfer(contract_address=token0, recipient=to, amount=diff0)
    IERC20.transfer(contract_address=token1, recipient=to, amount=diff1)

    ReentrancyGuard._end()

    return ()
end

# force reserves to match balances
@external
func sync{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}() -> ():
    alloc_locals

    ReentrancyGuard._start()

    let (token0) = _token0.read()
    let (token1) = _token1.read()
    let (self) = get_contract_address()
    let (balance0 : Uint256) = IERC20.balanceOf(contract_address=token0, account=self)
    let (balance1 : Uint256) = IERC20.balanceOf(contract_address=token1, account=self)
    let (reserve0) = _reserve0.read()
    let (reserve1) = _reserve1.read()

    _update(balance0, balance1, reserve0, reserve1)

    ReentrancyGuard._end()

    return ()
end

#
# Internal
#

func _mint_part1{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(
    to : felt,
    amount0 : Uint256,
    amount1 : Uint256,
    liquidity : Uint256,
    balance0 : Uint256,
    balance1 : Uint256,
    reserve0 : felt,
    reserve1 : felt,
):
    # Insufficient liquidity minted
    with_attr error_message("10kSwap: ILM"):
        let (is_le) = uint256_le(liquidity, Uint256(low=0, high=0))
        assert is_le = FALSE
    end

    _mint(to, liquidity)

    _update(balance0, balance1, reserve0, reserve1)
    # Todo
    # if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date

    let (sender) = get_caller_address()
    Mint.emit(sender, amount0, amount1)

    return ()
end

func _update{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(balance0 : Uint256, balance1 : Uint256, reserve0 : felt, reserve1 : felt):
    alloc_locals

    # Overflow
    with_attr error_message("10kSwap: OV"):
        let (is_le_0) = uint256_le(balance0, Uint256(low=Q112 - 1, high=0))
        let (is_le_1) = uint256_le(balance1, Uint256(low=Q112 - 1, high=0))
        assert (is_le_0, is_le_1) = (TRUE, TRUE)
    end

    let (blockTimestampLast) = _blockTimestampLast.read()
    let (price0CumulativeLast : Uint256) = _price0CumulativeLast.read()
    let (price1CumulativeLast : Uint256) = _price1CumulativeLast.read()

    let (block_timestamp) = get_block_timestamp()
    let (bt_r) = warp_mod(block_timestamp, 2 ** 32)
    let (block_timestamp) = warp_int128_to_int32(bt_r)

    # overflow is desired
    let timeElapsed = block_timestamp - blockTimestampLast

    let (if0) = warp_gt(timeElapsed, 0)
    let (if1) = warp_neq(reserve0, 0)
    let (if2) = warp_neq(reserve1, 0)
    let (b0) = bitwise_and(if0, if1)
    let (b1) = bitwise_and(b0, if2)
    if b1 == TRUE:
        let (e0) = encode(reserve0)
        let (e1) = encode(reserve1)
        let (u0) = uqdiv(e1, reserve0)
        let (u1) = uqdiv(e0, reserve1)

        # * never overflows, and + overflow is desired
        # _price0CumulativeLast = _price0CumulativeLast + u0 * timeElapsed
        let (p0 : Uint256) = warp_mul256(Uint256(low=u0, high=0), Uint256(low=timeElapsed, high=0))
        let (p1 : Uint256) = warp_mul256(Uint256(low=u1, high=0), Uint256(low=timeElapsed, high=0))
        let (p0CumulativeLast : Uint256) = warp_add256(p0, price0CumulativeLast)
        let (p1CumulativeLast : Uint256) = warp_add256(p1, price1CumulativeLast)
        _price0CumulativeLast.write(p0CumulativeLast)
        _price1CumulativeLast.write(p1CumulativeLast)

        # if condition will revoked implicit arguments
        # https://www.cairo-lang.org/docs/how_cairo_works/builtins.html?highlight=revoke%20reference#revoked-implicit-arguments
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    # Stroage
    let (r0) = warp_int256_to_int112(balance0)
    _reserve0.write(r0)
    let (r1) = warp_int256_to_int112(balance1)
    _reserve1.write(r1)
    _blockTimestampLast.write(block_timestamp)

    Sync.emit(r0, r1)

    return ()
end

# if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
func _mintFee{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    reserve0 : felt, reserve1 : felt
) -> (feeOn : felt):
    # address feeTo = IUniswapV2Factory(factory).feeTo();
    #     feeOn = feeTo != address(0);
    #     uint _kLast = kLast; // gas savings
    #     if (feeOn) {
    #         if (_kLast != 0) {
    #             uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
    #             uint rootKLast = Math.sqrt(_kLast);
    #             if (rootK > rootKLast) {
    #                 uint numerator = totalSupply.mul(rootK.sub(rootKLast));
    #                 uint denominator = rootK.mul(5).add(rootKLast);
    #                 uint liquidity = numerator / denominator;
    #                 if (liquidity > 0) _mint(feeTo, liquidity);
    #             }
    #         }
    #     } else if (_kLast != 0) {
    #         kLast = 0;
    #     }
    return (0)
end

func _mint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient : felt, amount : Uint256
):
    with_attr error_message("ERC20: amount is not a valid Uint256"):
        uint256_check(amount)
    end

    # Remove zero address check
    # with_attr error_message("ERC20: cannot mint to the zero address"):
    #     assert_not_zero(recipient)
    # end

    let (supply : Uint256) = ERC20_total_supply.read()
    with_attr error_message("ERC20: mint overflow"):
        let (new_supply : Uint256) = SafeUint256.add(supply, amount)
    end
    ERC20_total_supply.write(new_supply)

    let (balance : Uint256) = ERC20_balances.read(account=recipient)
    # overflow is not possible because sum is guaranteed to be less than total supply
    # which we check for overflow below
    let (new_balance : Uint256) = SafeUint256.add(balance, amount)
    ERC20_balances.write(recipient, new_balance)

    Transfer.emit(0, recipient, amount)
    return ()
end

func _burn{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    account : felt, amount : Uint256
):
    with_attr error_message("ERC20: amount is not a valid Uint256"):
        uint256_check(amount)
    end

    # Remove zero address check
    # with_attr error_message("ERC20: cannot burn from the zero address"):
    #     assert_not_zero(account)
    # end

    let (balance : Uint256) = ERC20_balances.read(account)
    with_attr error_message("ERC20: burn amount exceeds balance"):
        let (new_balance : Uint256) = SafeUint256.sub_le(balance, amount)
    end

    ERC20_balances.write(account, new_balance)

    let (supply : Uint256) = ERC20_total_supply.read()
    let (new_supply : Uint256) = SafeUint256.sub_le(supply, amount)
    ERC20_total_supply.write(new_supply)
    Transfer.emit(account, 0, amount)
    return ()
end

#
# Pair === end ===
#
