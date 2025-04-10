trait Searchable(Copyable, Movable):
    """How to allow a trait to return something that references the struct member that implements it.
    """

    fn buffer_to_search(ref self) -> Span[UInt8, __origin_of(self)]:
        ...


@value
struct PointerRecord(Searchable):
    var name: List[UInt8]
    var seq: List[UInt8]

    fn buffer_to_search(ref self) -> Span[UInt8, __origin_of(self)]:
        return Span[UInt8, __origin_of(self)](
            ptr=self.seq.unsafe_ptr(), length=len(self.seq)
        )


@value
struct RebindRecord(Searchable):
    var name: List[UInt8]
    var seq: List[UInt8]

    fn buffer_to_search(ref self) -> Span[UInt8, __origin_of(self)]:
        # https://forum.modular.com/t/how-to-return-a-span-that-refers-to-a-struct-member-from-a-trait-method/1216/4?u=duck_tape
        return rebind[Span[UInt8, __origin_of(self)]](Span(self.seq))


fn some_of_both_spans[
    oa: ImmutableOrigin, ob: ImmutableOrigin
](a: Span[ExpensiveThing, oa], b: Span[ExpensiveThing, ob]) -> List[
    Pointer[ExpensiveThing, __origin_of(oa, ob)]
]:
    """How to create a combination of lifetimes."""
    alias PType = Pointer[ExpensiveThing, __origin_of(oa, ob)]
    var ret = List[PType]()
    ret.append(PType(to=a[0]))
    ret.append(PType(to=b[1]))
    return ret


@value
struct ExpensiveThing:
    var value: Int


def main():
    var a = List(
        ExpensiveThing(1),
        ExpensiveThing(2),
        ExpensiveThing(3),
        ExpensiveThing(4),
    )
    var b = List(
        ExpensiveThing(4),
        ExpensiveThing(5),
        ExpensiveThing(6),
        ExpensiveThing(7),
    )
    # How to get specifically immutable versions of this.
    var mix = some_of_both_spans(
        Span(a).get_immutable(), Span(b).get_immutable()
    )
    print(mix[0][].value)
