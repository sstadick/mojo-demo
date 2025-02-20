trait Iterator:
    """Iterators are currently a bit magic in Mojo.

    If you want to be able to call `for item in items`, you need to implement
    these methods, which aren't documented anywhere.
    """

    alias EltType: AnyType

    fn __iter__(self) -> Self:
        ...

    fn __has_next__(read self) -> Bool:
        ...

    fn __next__(mut self) -> EltType:
        ...

    fn __len__(read self) -> Int:
        ...


trait CollectionIter(Iterator):
    alias EltType: CollectionElement


trait BaseIter:
    fn __iter__(self) -> Self:
        ...

    fn __has_next__(read self) -> Bool:
        ...

    fn __next__(mut self) -> AnyType:
        ...

    fn __len__(read self) -> Int:
        ...

    fn __moveinit__(out self, owned other: Self):
        ...


fn every_item[I: CollectionIter](mut iter: I) -> List[I.EltType]:
    var items = List[I.EltType]()
    for item in iter:
        items.append(item)
    return items


@value
struct ListIterator[
    src_mut: Bool, //, src_origin: Origin[src_mut], T: CollectionElement
]:
    """Iterate over values in a list."""

    var index: Int
    """Index into our underlying list."""
    var src: Pointer[List[T], src_origin]
    """The list to track."""

    fn __init__(out self, ref [src_origin]src: List[T]):
        self.index = 0
        self.src = Pointer.address_of(src)

    fn __iter__(self) -> Self:
        return self

    fn __has_next__(read self) -> Bool:
        return self.__len__() > 0

    fn __next__(mut self) -> Pointer[T, src_origin]:
        var p = Pointer.address_of(self.src[][self.index])
        self.index += 1
        return p

    fn __len__(read self) -> Int:
        return len(self.src[]) - self.index


fn main() raises:
    var values = List(1, 2, 3, 4, 5, 6, 7, 8, 9, 10)

    var values_iter = ListIterator(values)
    for item in values_iter:
        print(item[])

    # var items = every_item(
    #     values.__iter__()
    # )  # this fails, can't deduce the type of I, _ListIter does not conform to CollectionIter
    # # _ListIter has no associated type EltType, just a generic `T`. And traits don't support generics.
    # print(items)
