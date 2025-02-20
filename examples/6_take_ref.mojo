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


fn use_thing[origin: ImmutableOrigin](y: Pointer[MyThing, origin]):
    print(y[].thing)


fn use_thing[origin: MutableOrigin](y: Pointer[MyThing, origin]):
    y[].thing = String("I can overwrite this!")
    print(y[].thing)


fn as_mut[
    T: AnyType, origin: MutableOrigin
](ref [origin]arg: T) -> Pointer[T, origin]:
    return Pointer.address_of(arg)


fn as_read[
    T: AnyType, origin: ImmutableOrigin
](ref [origin]arg: T) -> Pointer[T, origin]:
    return Pointer.address_of(arg)


fn main():
    var e = MyThing("Hello, World!")
    use_thing(as_read(e))
    use_thing(as_mut(e))
