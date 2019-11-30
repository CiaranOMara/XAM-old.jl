# SAM Reader
# =========

mutable struct Reader{S <: TranscodingStream} <: BioGenerics.IO.AbstractReader
    state::State{S}
    header::Header
end


function Reader(state::State{S}) where {S <: TranscodingStream}

    state.state = sam_header_machine.start_state

    rdr = Reader(state, Header())

    # readheader!(rdr)
    # cs, ln, f = readheader!(rdr.state.stream, rdr, (rdr.state.state, rdr.state.linenum))
    readheader!(rdr.state.stream, rdr, (rdr.state.state, rdr.state.linenum))

    rdr.state.state = sam_body_machine.start_state
    return rdr
end

"""
    SAM.Reader(input::IO)

Create a data reader of the SAM file format.

# Arguments
* `input`: data source
"""
function Reader(input::IO)

    # return Reader(BufferedStreams.BufferedInputStream(input))

    if input isa TranscodingStream
        return Reader(State(input, 1, 1, false))
    end

    stream = TranscodingStreams.NoopStream(input)
    return Reader(State(stream, 1, 1, false))

end

function Base.eltype(::Type{<:Reader})
    return Record
end

function BioGenerics.IO.stream(reader::Reader)
    return reader.state.stream
end

"""
    header(reader::Reader)::Header

Get the header of `reader`.
"""
function BioGenerics.header(reader::Reader)::Header
    return reader.header
end

# function BioGenerics.header(reader::Reader)
#     return header(reader)
# end

function Base.close(reader::Reader)
    if reader.state.stream isa IO
        close(reader.state.stream)
    end
    return nothing
end

function index!(record::MetaInfo)
    stream = TranscodingStreams.NoopStream(IOBuffer(record.data))
    cs, linenum, found = readmetainfo!(stream, record, (1, 1))
    # if !found || !allspace(stream)
    if !found
        throw(ArgumentError("invalid SAM meta data"))
    end
    return record
end

function index!(record::Record)
    stream = TranscodingStreams.NoopStream(IOBuffer(record.data))
    cs, linenum, found = readrecord!(stream, record, (1, 1))
    # if !found || !allspace(stream)
    if !found
        throw(ArgumentError("invalid SAM record"))
    end
    return record
end

function Base.read!(rdr::Reader, rec::MetaInfo)
    cs, ln, f = readmetainfo!(rdr.state.stream, rec, (rdr.state.state, rdr.state.linenum))
    rdr.state.state = cs
    rdr.state.linenum = ln
    rdr.state.filled = f
    if !f
        cs == 0 && throw(EOFError())
        throw(ArgumentError("malformed SAM metainfo"))
    end
    return rec
end

function Base.read!(rdr::Reader, rec::Record)
    cs, ln, f = readrecord!(rdr.state.stream, rec, (rdr.state.state, rdr.state.linenum))
    rdr.state.state = cs
    rdr.state.linenum = ln
    rdr.state.filled = f
    if !f
        cs == 0 && throw(EOFError())
        throw(ArgumentError("malformed SAM file"))
    end
    return rec
end
