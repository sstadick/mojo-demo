# TODO: fill in sharp edges


trait StackLike:
    alias EltType: CollectionElement  # A type that implements CollectionElement

    fn pop(mut self) -> Self.EltType:
        ...


@value  # derives `__init__`, `__copyinit__`, `__moveinit__` for you.
struct MyStack[T: CollectionElement](StackLike):
    alias EltType = T
    var list: List[T]

    fn pop(mut self) -> Self.EltType:
        return self.list.pop()

    fn dump[U: RepresentableCollectionElement](self: MyStack[U]):
        """Make use of conditional conformance here.

        If our type T conforms to U, then this is a callable method. It's not required
        that a user of MyStack make sure their type conforms to this, but if it does they
        get extra functionality.
        """
        print(self.list.__repr__())


fn main() raises:
    var stack = MyStack(List(1, 2, 3, 4, 5))
    var item = stack.pop()
    print(item)


trait Quackable:
    fn quack(self):
        ...


# https://docs.modular.com/mojo/manual/decorators/register-passable/
@value
@register_passable("trivial")
struct Duck(Quackable):
    fn quack(self):
        print("QUACK")


@value
struct RubberDucky:
    fn quack(self):
        print("Squeak")


fn make_it_quack[T: Quackable](maybe_a_duck: T):
    maybe_a_duck.quack()


fn test():
    var duck = Duck()
    var rubber_duck = RubberDucky()
    make_it_quack(duck)
    make_it_quack(rubber_duck)  # It works!
    # This is called implicit trait conformance
    # Adjacent to structural typing
    # Not encouraged, but useful to know about, especially
    # when working with code you can't control.
    # You can create a trait that matches the outside functionality
    # and use it as an interface even thought he external code doesn't specifically
    # implement your trait.
