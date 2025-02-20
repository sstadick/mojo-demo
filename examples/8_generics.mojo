@value  # derives `__init__`, `__copyinit__`, `__moveinit__` for you.
struct MyStack[T: CollectionElement]:
    var list: List[T]

    fn pop(mut self) -> T:
        return self.list.pop()


fn main() raises:
    var stack = MyStack(List(1, 2, 3, 4, 5))
    var item = stack.pop()
    print(item)
