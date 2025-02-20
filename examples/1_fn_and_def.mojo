def create_greeting(name, *, cordial_msg=""):
    """`def` functions don't require type declarations, undeclared types are just `object`.

    `def` function arguments are mutable and follow the Python convention of "pass by object reference".
    """
    special_greeting = "Hello, " + name + "! " + cordial_msg
    return special_greeting


fn fast_greeting(
    read name: String, *, read cordial_msg: String = "Yo!"
) -> String:
    """`fn` functions require explicit typing.

    `fn` functions can specify how they want to receive arguments (read, mut, owned, ref).
    """
    var special_greeting = String("Hello", name, "!", cordial_msg, sep=" ")
    return special_greeting


fn main() raises:
    """Demonstrate the two different "worlds" in Mojo."""
    var msg = create_greeting("Seth", cordial_msg="What's up!")
    print(msg)

    var fast_hello = fast_greeting("Seth", cordial_msg="Sup!")
    print(fast_hello)
