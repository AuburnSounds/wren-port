module wren.optional.random;
import wren.vm;
import wren.common;

static if (WREN_OPT_RANDOM):

private static const(char)[] randomModuleSource = import("optional/wren_opt_random.wren");

// Implements the well equidistributed long-period linear PRNG (WELL512a).
//
// https://en.wikipedia.org/wiki/Well_equidistributed_long-period_linear
struct Well512
{
    uint[32] state;
    uint index;
}

// Code from: http://www.lomont.org/Math/Papers/2008/Lomont_PRNG_2008.pdf
uint advanceState(Well512* well) @nogc
{
    uint a, b, c, d;
    a = well.state[well.index];
    c = well.state[(well.index + 13) & 15];
    b =  a ^ c ^ (a << 16) ^ (c << 15);
    c = well.state[(well.index + 9) & 15];
    c ^= (c >> 11);
    a = well.state[well.index] = b ^ c;
    d = a ^ ((a << 5) & 0xda442d24U);

    well.index = (well.index + 15) & 15;
    a = well.state[well.index];
    well.state[well.index] = a ^ b ^ d ^ (a << 2) ^ (b << 18) ^ (c << 28);
    return well.state[well.index];
}

void randomAllocate(WrenVM* vm) @nogc
{
    Well512* well = cast(Well512*)wrenSetSlotNewForeign(vm, 0, 0, Well512.sizeof);
    well.index = 0;
}

void randomSeed0(WrenVM* vm) @nogc
{
    import core.stdc.stdlib : srand, rand;
    import core.stdc.time : time;

    Well512* well = cast(Well512*)wrenGetSlotForeign(vm, 0);

    srand(cast(uint)time(null));
    for (int i = 0; i < 16; i++)
    {
        well.state[i] = rand();
    }
}

void randomSeed1(WrenVM* vm) @nogc
{
    import core.stdc.stdlib : srand, rand;
    Well512* well = cast(Well512*)wrenGetSlotForeign(vm, 0);

    srand(cast(uint)wrenGetSlotDouble(vm, 1));
    for (int i = 0; i < 16; i++)
    {
        well.state[i] = rand();
    }
}

void randomSeed16(WrenVM* vm) @nogc
{
    Well512* well = cast(Well512*)wrenGetSlotForeign(vm, 0);

    for (int i = 0; i < 16; i++)
    {
        well.state[i] = cast(uint)wrenGetSlotDouble(vm, i + 1);
    }
}

void randomFloat(WrenVM* vm) @nogc
{
    Well512* well = cast(Well512*)wrenGetSlotForeign(vm, 0);

    // A double has 53 bits of precision in its mantissa, and we'd like to take
    // full advantage of that, so we need 53 bits of random source data.

    // First, start with 32 random bits, shifted to the left 21 bits.
    double result = cast(double)advanceState(well) * (1 << 21);

    // Then add another 21 random bits.
    result += cast(double)(advanceState(well) & ((1 << 21) - 1));

    // Now we have a number from 0 - (2^53). Divide be the range to get a double
    // from 0 to 1.0 (half-inclusive).
    result /= 9007199254740992.0;

    wrenSetSlotDouble(vm, 0, result);
}

void randomInt0(WrenVM* vm) @nogc
{
    Well512* well = cast(Well512*)wrenGetSlotForeign(vm, 0);

    wrenSetSlotDouble(vm, 0, cast(double)advanceState(well));
}

const(char)[] wrenRandomSource() @nogc
{
    return randomModuleSource;
}

WrenForeignClassMethods wrenRandomBindForeignClass(WrenVM* vm,
                                                    const(char)* module_,
                                                    const(char)* className) @nogc
{
    import core.stdc.string : strcmp;
    assert(strcmp(className, "Random") == 0, "Should be in Random class.");
    WrenForeignClassMethods methods;
    methods.allocate = &randomAllocate;
    methods.finalize = null;
    return methods;
}

WrenForeignMethodFn wrenRandomBindForeignMethod(WrenVM* vm,
                                                const(char)* className,
                                                bool isStatic,
                                                const(char)* signature) @nogc
{
    import core.stdc.string : strcmp;
    assert(strcmp(className, "Random") == 0, "Should be in Random class.");

    if (strcmp(signature, "<allocate>") == 0) return &randomAllocate;
    if (strcmp(signature, "seed_()") == 0) return &randomSeed0;
    if (strcmp(signature, "seed_(_)") == 0) return &randomSeed1;
        
    if (strcmp(signature, "seed_(_,_,_,_,_,_,_,_,_,_,_,_,_,_,_,_)") == 0)
    {
        return &randomSeed16;
    }
    
    if (strcmp(signature, "float()") == 0) return &randomFloat;
    if (strcmp(signature, "int()") == 0) return &randomInt0;

    assert(0, "Unknown method.");
}