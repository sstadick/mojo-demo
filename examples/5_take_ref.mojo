struct MyThing:
    var thing: String

    fn __init__(out self, thing: String):
        self.thing = thing

    fn __copyinit__(out self, read existing: Self):
        print("Called MyThing __copyinit__")
        self.thing = existing.thing

    fn __moveinit__(out self, owned existing: Self):
        print("Called MyThing __moveinit__")
        self.thing = existing.thing^


fn take_ref[
    is_mutable: Bool, //, origin: Origin[is_mutable]
](y: Pointer[MyThing, origin]):
    """A function that takes a reference that is parametric over mutability."""

    @parameter
    if is_mutable:
        # https://forum.modular.com/t/should-this-parametric-mutability-example-work/574/10
        # Rebind is needed when we have additional information about a type that isn't obvious to the compiler.
        # In this case the compiler doesn't do type refinement (narrowing) to make use of the information in my
        # `if is_mutable` to know that y is mutable.
        # Mojo won’t let you mutate something with a parametric mutability, because it isn’t valid for all instantiations
        # of the code. So the rebind in this case is the correct way to go.
        var y_mut = rebind[
            Pointer[MyThing, MutableOrigin.cast_from[origin].result]
        ](y)
        y_mut[].thing = String("Can overwrite it")
    else:
        print("This is sad, we can't mutate it :(")

    print(y[].thing)


fn take_owned(owned y: MyThing):
    print(y.thing)


fn take_read(read y: MyThing):
    # This would be an immutable pointer
    var ptr = Pointer.address_of(y)
    take_ref(ptr)


fn main():
    var e = MyThing("Hello, World!")
    var x = Pointer.address_of(e)  # extremely similar to "pass by ref"
    take_ref(Pointer.address_of(e))
    # take_owned(e^) # If we passed ownership of e, we get an error that x may now be invalid
    x[].thing = String("hi")
    print(e.thing)
    print(x[].thing)

    # In what context would an immutable pointer be created?
    take_read(e)
