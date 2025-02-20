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


fn take_read(read y: MyThing):
    """A function that takes an immutable reference of a MyThing."""
    print("take immutable")
    # y = MyThing("Overwrite it") # would fail because y isn't mutable
    print(y.thing)


fn main():
    var c = MyThing("Hello, World!")
    take_read(c)  # No copies / moves are needed
    print(c.thing)
