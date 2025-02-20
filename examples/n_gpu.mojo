"""
## References

- https://docs.modular.com/mojo/stdlib/gpu/
"""

"""
# MAX

We need to talk about MAX. I don't fully understand MAX.

MAX is how Modular makes money, at least for now. It's library that runs GenAI models,
and runs them faster and more easily than other things that you can deploy models with.

It does this with MAX Engine, it's super awesome (according to itself) graph compiler and 
runtime.

For the most part, MAX is currently targeted at Python, with a very well built out Python API.
Its mojo API is lacking, but improving.

All GPU support is in service of MAX, as far as I can tell at the moment. 

MAX can run mdels in ONNX format.

Example of running deepseek locally using MAX (choosing the CPU target)
- https://builds.modular.com/models/DeepSeek-R1-Distill-Llama/gguf_8B


## Highish Level Maybe Wrong Words

MAX is a graph compiler. It allows taking a series of operations, and then will do a bunch of work
to make that series of operations as performant as possible. Specifically, you describe a "graph" of
operations, and then it will compile that.

Once it's been compiled, you can "run" it and give it data. When it's running, it's loaded the compiled
representation of your graph and that's what's being executed.

I don't see obvious support for running operations on the GPU outside of a graph, but I suspect it's 
there and just not well documented right now. Additionally, if you are doing heavy GPU compute, it's likely
that you would benefit from describing that compute in terms of a graph that the graph compiler could
work on.

# GPU Support

It's not based on CUDA. This is one of their value propositions. They are aiming to allow non Nvidia
GPUs to compete it seem, which has potential to really shift the current balance of power.

It's not fully baked yet, as mentioned above, they've been building it out as-needed for MAX.

They don't support _all_ GPUs yet, just a small subset, mostly aimed a the higher end GPUs used in 
datacenters for AI.

# Examples

There are no examples that aren't part of / managed by MAX that I can find at this time.

 - MAX: https://github.com/modular/max/blob/main/examples/custom_ops/kernels/vector_addition.mojo
 - MAX/MOJO: Build a custom kernel with Mojo and then use it MAX
    - https://docs.modular.com/max/tutorials/build-custom-ops
    - https://github.com/modular/max/blob/main/examples/custom_ops/addition.py
"""
