#=
@inline function anchor!(stream::BufferedStreams.BufferedInputStream, p, immobilize = true)
    stream.anchor = p
    stream.immobilized = immobilize
    return stream
end

@inline function upanchor!(stream::BufferedStreams.BufferedInputStream)
    @assert stream.anchor != 0 "upanchor! called with no anchor set"
    anchor = stream.anchor
    stream.anchor = 0
    stream.immobilized = false
    return anchor
end

function ensure_margin!(stream::BufferedStreams.BufferedInputStream)
    if stream.position * 20 > length(stream.buffer) * 19
        BufferedStreams.shiftdata!(stream)
    end
    return nothing
end

@inline function resize_and_copy!(dst::Vector{UInt8}, src::Vector{UInt8}, r::UnitRange{Int})
    return resize_and_copy!(dst, 1, src, r)
end

@inline function resize_and_copy!(dst::Vector{UInt8}, dstart::Int, src::Vector{UInt8}, r::UnitRange{Int})
    rlen = length(r)
    if length(dst) != dstart + rlen - 1
        resize!(dst, dstart + rlen - 1)
    end
    copyto!(dst, dstart, src, first(r), rlen)
    return dst
end

function generate_index_function(record_type, machine, init_code, actions; kwargs...)
    kwargs = Dict(kwargs)
    context = Automa.CodeGenContext(
        generator = get(kwargs, :generator, :goto),
        checkbounds = get(kwargs, :checkbounds, false),
        loopunroll = get(kwargs, :loopunroll, 0)
    )
    quote
        function index!(record::$(record_type))
            data = record.data
            p = 1
            p_end = p_eof = sizeof(data)
            initialize!(record)
            $(init_code)
            cs = $(machine.start_state)
            $(Automa.generate_exec_code(context, machine, actions))
            if cs != 0
                throw(ArgumentError(string("failed to index ", $(record_type), " ~>", repr(String(data[p:min(p+7,p_end)])))))
            end
            @assert isfilled(record)
            return record
        end
    end
end

function generate_readheader_function(reader_type, metainfo_type, machine, init_code, actions, finish_code=:())
    quote
        function readheader!(reader::$(reader_type))
            _readheader!(reader, reader.state)
        end

        function _readheader!(reader::$(reader_type), state::State)
            stream = state.stream
            ensure_margin!(stream)
            cs = state.cs
            linenum = state.linenum
            data = stream.buffer
            p = stream.position
            p_end = stream.available
            p_eof = -1
            finish_header = false
            record = $(metainfo_type)()

            $(init_code)

            while true
                $(Automa.generate_exec_code(Automa.CodeGenContext(generator=:table), machine, actions))

                state.cs = cs
                state.finished = cs == 0
                state.linenum = linenum
                stream.position = p

                if cs < 0
                    error("$($(reader_type)) file format error on line ", linenum)
                elseif finish_header
                    $(finish_code)
                    break
                elseif p > p_eof ≥ 0
                    error("incomplete $($(reader_type)) input on line ", linenum)
                else
                    hits_eof = BufferedStreams.fillbuffer!(stream) == 0
                    p = stream.position
                    p_end = stream.available
                    if hits_eof
                        p_eof = p_end
                    end
                end
            end
        end
    end
end

function generate_read_function(reader_type, machine, init_code, actions; kwargs...)
    kwargs = Dict(kwargs)
    context = Automa.CodeGenContext(
        generator=get(kwargs, :generator, :goto),
        checkbounds=get(kwargs, :checkbounds, false),
        loopunroll=get(kwargs, :loopunroll, 0)
    )
    quote
        function Base.read!(reader::$(reader_type), record::eltype($(reader_type)))::eltype($(reader_type))
            return _read!(reader, reader.state, record)
        end

        function _read!(reader::$(reader_type), state::State, record::eltype($(reader_type)))
            stream = state.stream
            ensure_margin!(stream)
            cs = state.cs
            linenum = state.linenum
            data = stream.buffer
            p = stream.position
            p_end = stream.available
            p_eof = -1
            found_record = false
            initialize!(record)

            $(init_code)

            if state.finished
                throw(EOFError())
            end

            while true
                $(Automa.generate_exec_code(context, machine, actions))

                state.cs = cs
                state.finished |= cs == 0
                state.linenum = linenum
                stream.position = p

                if cs < 0
                    error($(reader_type), " file format error on line ", linenum, " ~>", repr(String(data[p:min(p+7,p_end)])))
                elseif found_record
                    break
                elseif cs == 0
                    throw(EOFError())
                elseif p > p_eof ≥ 0
                    error("incomplete $($(reader_type)) input on line ", linenum)
                elseif BufferedStreams.available_bytes(stream) < 64
                    hits_eof = BufferedStreams.fillbuffer!(stream) == 0
                    p = stream.position
                    p_end = stream.available
                    if hits_eof
                        p_eof = p_end
                    end
                end
            end

            @assert isfilled(record)
            return record
        end
    end
end
=#

# Automa.jl generated readrecord! and readmetainfo! functions
# ========================================

# file   = header . body
# header = metainfo*
# body   = record*
const sam_metainfo_machine, sam_record_machine, sam_header_machine, sam_body_machine = (function ()

    isinteractive() && info("compiling SAM")

    cat = Automa.RegExp.cat
    rep = Automa.RegExp.rep
    alt = Automa.RegExp.alt
    opt = Automa.RegExp.opt
    any = Automa.RegExp.any

    metainfo = let
        tag = re"[A-Z][A-Z]" \ cat("CO")
        tag.actions[:enter] = [:pos1]
        tag.actions[:exit]  = [:metainfo_tag]

        dict = let
            key = re"[A-Za-z][A-Za-z0-9]"
            key.actions[:enter] = [:pos2]
            key.actions[:exit]  = [:metainfo_dict_key]
            val = re"[ -~]+"
            val.actions[:enter] = [:pos2]
            val.actions[:exit]  = [:metainfo_dict_val]
            keyval = cat(key, ':', val)

            cat(keyval, rep(cat('\t', keyval)))
        end
        dict.actions[:enter] = [:pos1]
        dict.actions[:exit]  = [:metainfo_val]

        co = cat("CO")
        co.actions[:enter] = [:pos1]
        co.actions[:exit]  = [:metainfo_tag]

        comment = re"[^\r\n]*"
        comment.actions[:enter] = [:pos1]
        comment.actions[:exit]  = [:metainfo_val]

        cat('@', alt(cat(tag, '\t', dict), cat(co, '\t', comment)))
    end
    metainfo.actions[:enter] = [:mark]
    metainfo.actions[:exit]  = [:metainfo]

    record = let
        qname = re"[!-?A-~]+"
        qname.actions[:enter] = [:pos]
        qname.actions[:exit]  = [:record_qname]

        flag = re"[0-9]+"
        flag.actions[:enter] = [:pos]
        flag.actions[:exit]  = [:record_flag]

        rname = re"\*|[!-()+-<>-~][!-~]*"
        rname.actions[:enter] = [:pos]
        rname.actions[:exit]  = [:record_rname]

        pos = re"[0-9]+"
        pos.actions[:enter] = [:pos]
        pos.actions[:exit]  = [:record_pos]

        mapq = re"[0-9]+"
        mapq.actions[:enter] = [:pos]
        mapq.actions[:exit]  = [:record_mapq]

        cigar = re"\*|([0-9]+[MIDNSHPX=])+"
        cigar.actions[:enter] = [:pos]
        cigar.actions[:exit]  = [:record_cigar]

        rnext = re"\*|=|[!-()+-<>-~][!-~]*"
        rnext.actions[:enter] = [:pos]
        rnext.actions[:exit]  = [:record_rnext]

        pnext = re"[0-9]+"
        pnext.actions[:enter] = [:pos]
        pnext.actions[:exit]  = [:record_pnext]

        tlen = re"[-+]?[0-9]+"
        tlen.actions[:enter] = [:pos]
        tlen.actions[:exit]  = [:record_tlen]

        seq = re"\*|[A-Za-z=.]+"
        seq.actions[:enter] = [:pos]
        seq.actions[:exit]  = [:record_seq]

        qual = re"[!-~]+"
        qual.actions[:enter] = [:pos]
        qual.actions[:exit]  = [:record_qual]

        field = let
            tag = re"[A-Za-z][A-Za-z0-9]"
            val = alt(
                re"A:[!-~]",
                re"i:[-+]?[0-9]+",
                re"f:[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?",
                re"Z:[ !-~]*",
                re"H:([0-9A-F][0-9A-F])*",
                re"B:[cCsSiIf](,[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?)+")

            cat(tag, ':', val)
        end
        field.actions[:enter] = [:pos]
        field.actions[:exit]  = [:record_field]

        cat(
            qname, '\t',
            flag,  '\t',
            rname, '\t',
            pos,   '\t',
            mapq,  '\t',
            cigar, '\t',
            rnext, '\t',
            pnext, '\t',
            tlen,  '\t',
            seq,   '\t',
            qual,
            rep(cat('\t', field)))
    end
    record.actions[:enter] = [:mark]
    record.actions[:exit]  = [:record]

    newline = let
        lf = re"\n"
        lf.actions[:enter] = [:countline]

        cat(re"\r?", lf)
    end

    header′ = rep(cat(metainfo, newline))
    header′.actions[:exit] = [:header]
    header = cat(header′, opt(any() \ cat('@')))  # look ahead

    body = rep(cat(record, newline))

    return map(Automa.compile, (metainfo, record, header, body))
end)()

# write("sam_metainfo_machine.dot", Automa.machine2dot(sam_metainfo_machine))
# run(`dot -Tsvg -o sam_metainfo_machine.svg sam_metainfo_machine.dot`)
#
# write("sam_record_machine.dot", Automa.machine2dot(sam_record_machine))
# run(`dot -Tsvg -o sam_record_machine.svg sam_record_machine.dot`)
#
# write("sam_header_machine.dot", Automa.machine2dot(sam_header_machine))
# run(`dot -Tsvg -o sam_header_machine.svg sam_header_machine.dot`)
#
# write("sam_body_machine.dot", Automa.machine2dot(sam_body_machine))
# run(`dot -Tsvg -o sam_body_machine.svg sam_body_machine.dot`)

function appendfrom!(dst, dpos, src, spos, n)
    if length(dst) < dpos + n - 1
        resize!(dst, dpos + n - 1)
    end
    copyto!(dst, dpos, src, spos, n)
    return dst
end

const sam_metainfo_actions = Dict(
    :mark => :(@mark),
    :pos1  => :(pos1 = @relpos(p)),
    :pos2  => :(pos2 = @relpos(p)),
    :countline => :(linenum += 1),
    :metainfo_tag => :(metainfo.tag = pos1:@relpos(p-1)),
    :metainfo_val => :(metainfo.val = pos1:@relpos(p-1)),
    :metainfo_dict_key => :(push!(metainfo.dictkey, pos2:@relpos(p-1))),
    :metainfo_dict_val => :(push!(metainfo.dictval, pos2:@relpos(p-1))),
    :metainfo => quote
        appendfrom!(metainfo.data, 1, data, @markpos(), p-@markpos())
        # metainfo.filled = 1:@relpos(p-1)
        # metainfo.filled = 1:p-1
        # metainfo.filled = markpos:p
        metainfo.filled = @markpos():p-1
        found_metainfo = true
        @escape
    end
)

sam_metainfo_context = Automa.CodeGenContext(
    generator = :goto,
    checkbounds = false,
    loopunroll = 0
)

sam_metainfo_initcode = quote
    pos1 = 0
    pos2 = 0
    filled = 0
    found_metainfo = false
    initialize!(metainfo)
    cs, linenum = state
end

sam_metainfo_loopcode = quote
    if cs < 0
        throw(ArgumentError("malformed metainfo at line $(linenum)"))
    end
    found_metainfo && @goto __return__
end

sam_metainfo_returncode = quote
    return cs, linenum, found_metainfo
end

Automa.Stream.generate_reader(
    :readmetainfo!,
    sam_metainfo_machine,
    arguments = (:(metainfo::MetaInfo), :(state::Tuple{Int,Int})),
    actions = sam_metainfo_actions,
    context = sam_metainfo_context,
    initcode = sam_metainfo_initcode,
    loopcode = sam_metainfo_loopcode,
    returncode = sam_metainfo_returncode
) |> eval

const sam_header_actions = merge(
    sam_metainfo_actions,
    Dict(
        :metainfo => quote
            let markpos = @markpos()
                # appendfrom!(metainfo.data, filled + 1, data, markpos, n)
                # appendfrom!(metainfo.data, 1, data, markpos, @relpos(p-1))
                appendfrom!(metainfo.data, 1, data, markpos, p-markpos)

                # metainfo.filled = markpos:@relpos(p-1)
                # metainfo.filled = markpos:p
                metainfo.filled = markpos:p-1

                @info ":metainfo" p pos markpos @relpos(markpos)


                # filled += n
            end
        end,
        :header => quote
            finish_header = true
            @escape
        end
    )
)

sam_header_context = Automa.CodeGenContext(
    generator = :goto,
    checkbounds = false,
    loopunroll = 0
)

sam_header_initcode = quote
    @info "sam_header_initcode" state

    pos = 0
    # filled = 0
    found_metainfo = false
    finish_header = false
    metainfo = MetaInfo()
    cs, linenum = state
end

sam_header_loopcode = quote
    @info "sam_header_loopcode" state p pos metainfo.filled String(copy(metainfo.data))

    if cs < 0
        throw(ArgumentError("malformed metainfo at line $(linenum)"))
    end

    @assert isfilled(metainfo) #TODO: move to loopcode?

    push!(reader.header.metainfo, metainfo) #TODO: move to loopcode?

    metainfo = MetaInfo()

    finish_header && @goto __return__
end

sam_header_returncode = quote
    return cs, linenum, finish_header
end

Automa.Stream.generate_reader(
    :readheader!,
    sam_header_machine,
    arguments = (:(reader::Reader), :(state::Tuple{Int,Int})),
    actions = sam_header_actions,
    context = sam_header_context,
    initcode = sam_header_initcode,
    loopcode = sam_header_loopcode,
    returncode = sam_header_returncode
) |> eval

#=
generate_index_function(
    MetaInfo,
    sam_metainfo_machine,
    :(pos1 = pos2 = offset = 0),
    sam_metainfo_actions
) |> eval

generate_readheader_function(
    Reader,
    MetaInfo,
    sam_header_machine,
    :(pos1 = pos2 = offset = 0),
    merge(sam_metainfo_actions, Dict(
        :metainfo => quote
            resize_and_copy!(record.data, data, upanchor!(stream):p-1)
            record.filled = (offset+1:p-1) .- offset
            @assert isfilled(record)
            push!(reader.header.metainfo, record)
            ensure_margin!(stream)
            record = MetaInfo()
        end,
        :header => :(finish_header = true; @escape),
        :countline => :(linenum += 1),
        :mark => :(anchor!(stream, p); offset = p - 1))),
    quote
        if !eof(stream)
            stream.position -= 1  # cancel look-ahead
        end
    end
) |> eval
=#


const sam_record_actions = Dict(
    :mark => :(@mark),
    :pos => :(pos = @relpos(p)),
    :countline => :(linenum += 1),
    :record_qname => :(record.qname = pos:@relpos(p-1)),
    :record_flag  => :(record.flag  = pos:@relpos(p-1)),
    :record_rname => :(record.rname = pos:@relpos(p-1)),
    :record_pos   => :(record.pos   = pos:@relpos(p-1)),
    :record_mapq  => :(record.mapq  = pos:@relpos(p-1)),
    :record_cigar => :(record.cigar = pos:@relpos(p-1)),
    :record_rnext => :(record.rnext = pos:@relpos(p-1)),
    :record_pnext => :(record.pnext = pos:@relpos(p-1)),
    :record_tlen  => :(record.tlen  = pos:@relpos(p-1)),
    :record_seq   => :(record.seq   = pos:@relpos(p-1)),
    :record_qual  => :(record.qual  = pos:@relpos(p-1)),
    :record_field => :(push!(record.fields, pos:@relpos(p-1))),
    :record       => quote
        let markpos = @markpos()
            # appendfrom!(record.data, 1, data, markpos, p-@markpos)
            appendfrom!(record.data, 1, data, markpos, p-markpos)

            # record.filled = markpos:@relpos(p-1)
            # record.filled = @relpos(markpos):@relpos(p-1)
            # record.filled = markpos:p
            record.filled = markpos:p-1

            found_record = true

            @info ":record" p pos markpos @relpos(markpos)
            @escape
        end
    end
)

sam_record_context = Automa.CodeGenContext(
    generator = :goto,
    checkbounds = false,
    loopunroll = 0
)

sam_record_initcode = quote
    @info "sam_record_initcode" state

    pos = 0
    # filled = 0
    found_record = false
    initialize!(record)
    cs, linenum = state
end

sam_record_loopcode = quote
    @info "sam_record_loopcode" state p pos record.filled String(copy(record.data))

    if cs < 0
        throw(ArgumentError("malformed SAM file at line $(linenum)"))
    end
    found_record && @goto __return__
end

sam_record_returncode = quote
    return cs, linenum, found_record
end

Automa.Stream.generate_reader(
    :readrecord!,
    sam_body_machine,
    arguments = (:(record::Record), :(state::Tuple{Int,Int})),
    actions = sam_record_actions,
    context = sam_record_context,
    initcode = sam_record_initcode,
    loopcode = sam_record_loopcode,
    returncode = sam_record_returncode
) |> eval

#=
generate_index_function(
    Record,
    sam_record_machine,
    :(pos = offset = 0),
    sam_record_actions
) |> eval

generate_read_function(
    Reader,
    sam_body_machine,
    :(pos = offset = 0),
    merge(sam_record_actions, Dict(
        :record    => quote
            resize_and_copy!(record.data, data, upanchor!(stream):p-1)
            record.filled = (offset+1:p-1) .- offset
            found_record = true
            @escape
        end,
        :countline => :(linenum += 1),
        :mark    => :(anchor!(stream, p); offset = p - 1))
    )
) |> eval
=#
