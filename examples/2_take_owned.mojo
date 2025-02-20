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


fn take_ownership(owned y: MyThing):
    """A function that takes ownership of a MyString."""
    y = MyThing("Overwrite it")
    print(y.thing)


fn main() raises:
    var x = MyThing("Hello, World!")
    take_ownership(x^)  # the ^ indicates that x is moved into y
    # print(x.thing)  # This results in a compile time error since x is now invalid
    # Ownership of x has been passed to `take_ownership`, neither __moveinit__ nor __copyinit__
    # is called

    var z = MyThing("Hello, World!")
    take_ownership(
        z
    )  # Without the ^ here, z is copied into y via `__copyinit__`
    print(
        z.thing
    )  # if we don't have this print, there will be no copy of z and it's transferred

    var a = MyThing("Hello, World!")
    var b = a  # a is moved into b via the `__moveinit__` if it's implemented, or `__copyinit__`.
    # If neither are implemented then the value can't be transferred.
    # print(a) # Can't be called
    print(
        b.thing
    )  # Similar to above, if there are no more uses of a, a is just transferred to b
