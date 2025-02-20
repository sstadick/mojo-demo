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


fn take_mut(mut y: MyThing):
    """A function that takes an mutable reference of a MyThing."""
    print("take mutable")
    y.thing = "Overwrite it!"
    # y = MyThing("Overwrite it, again!") # also works
    print(y.thing)


fn main():
    var d = MyThing("Hello, World!")
    take_mut(d)  # No copies or moves are needed
    print(d.thing)
