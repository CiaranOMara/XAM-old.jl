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


function appendfrom!(dst, dpos, src, spos, n)
    if length(dst) < dpos + n - 1
        resize!(dst, dpos + n - 1)
    end
    copyto!(dst, dpos, src, spos, n)
    return dst
end

const sam_metainfo_actions = Dict(
    :mark => :(@mark),
    # :pos => :(pos = @relpos(p)),
    :pos1  => :(pos1 = @relpos(p)),
    :pos2  => :(pos2 = @relpos(p)),
    :countline => :(linenum += 1),
    :metainfo_tag => :(record.tag = pos1:@relpos(p-1)),
    :metainfo_val => :(record.val = pos1:@relpos(p-1)),
    :metainfo_dict_key => :(push!(record.dictkey, pos2:@relpos(p-1))),
    :metainfo_dict_val => :(push!(record.dictval, pos2:@relpos(p-1))),
    # :metainfo => quote
    #     resize_and_copy!(record.data, data, offset+1:p-1)
    #     record.filled = (offset+1:p-1) .- offset
    # end,
    :metainfo => quote
        # record.filled = 1:filled
        record.filled = 1:@relpos(p-1)
        found = true
        @escape
    end

)

sam_metainfo_context = Automa.CodeGenContext(
    generator = :goto,
    checkbounds = false,
    loopunroll = 0
)

sam_metainfo_initcode = quote
    pos = 0
    filled = 0
    found = false
    initialize!(record)
    cs, linenum = state
end

sam_metainfo_loopcode = quote
    if cs < 0
        throw(ArgumentError("malformed metainfo at line $(linenum)"))
    end
    found && @goto __return__
end

sam_metainfo_returncode = quote
    return cs, linenum, found
end

Automa.Stream.generate_reader(
    :readmetainfo!,
    sam_metainfo_machine,
    arguments = (:(record::MetaInfo), :(state::Tuple{Int,Int})),
    actions = sam_metainfo_actions,
    context = sam_metainfo_context,
    initcode = sam_metainfo_initcode,
    loopcode = sam_metainfo_loopcode,
    returncode = sam_metainfo_returncode
) |> eval


const sam_header_actions = merge(
    sam_metainfo_actions,
    Dict(
        # :metainfo => quote
        #     # resize_and_copy!(record.data, data, upmark!(stream):p-1)
        #     # record.filled = (offset+1:p-1) .- offset
        #
        #     # let n = p - @markpos
        #     #     appendfrom!(record.data, 1, data, @markpos, n)
        #     #     # record.filled += n
        #     #     # record.filled = 1:@relpos(p-1)
        #     #     record.filled = @markpos:n'
        #     # end
        #
        #     record.filled = 1:@relpos(p-1)
        #
        #
        # end,
        :metainfo => quote
            record.filled = 1:@relpos(p-1)
            found = true
            #Note: overwriting to remove escape.
        end,
        :header => quote
            finish_header = true
            @escape
        end,
        # :countline => :(linenum += 1),
        # :mark => :(mark!(stream, p); offset = p - 1)
    )
)

sam_header_context = Automa.CodeGenContext(
    generator = :goto,
    checkbounds = false,
    loopunroll = 0
)

sam_header_initcode = quote
    pos = 0
    filled = 0
    found = false
    # initialize!(record)
    record = MetaInfo()
    cs, linenum = state
end

sam_header_loopcode = quote
    if cs < 0
        throw(ArgumentError("malformed metainfo at line $(linenum)"))
    end

    @assert isfilled(record) #TODO: move to loopcode?

    push!(reader.header.metainfo, record) #TODO: move to loopcode?

    record = MetaInfo()

    # found && @goto __return__
    finish_header && @goto __return__
end

sam_header_returncode = quote
    return cs, linenum, found
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

const sam_record_actions = Dict(
    :mark => :(@mark),
    :pos => :(pos = @relpos(p)),
    :countline => :(linenum += 1),

    :record_qname => :(record.qname = (pos:@relpos(p-1))),
    :record_flag  => :(record.flag  = (pos:@relpos(p-1))),
    :record_rname => :(record.rname = (pos:@relpos(p-1))),
    :record_pos   => :(record.pos   = (pos:@relpos(p-1))),
    :record_mapq  => :(record.mapq  = (pos:@relpos(p-1))),
    :record_cigar => :(record.cigar = (pos:@relpos(p-1))),
    :record_rnext => :(record.rnext = (pos:@relpos(p-1))),
    :record_pnext => :(record.pnext = (pos:@relpos(p-1))),
    :record_tlen  => :(record.tlen  = (pos:@relpos(p-1))),
    :record_seq   => :(record.seq   = (pos:@relpos(p-1))),
    :record_qual  => :(record.qual  = (pos:@relpos(p-1))),
    :record_field => :(push!(record.fields, (pos:@relpos(p-1)))),
    :record       => quote
        # resize_and_copy!(record.data, data, 1:p-1)
        # record.filled = (offset+1:p-1) .- offset
        # record.filled = 1:filled
        record.filled = 1:@relpos(p-1)
        found = true
        @escape
    end
    # :mark       => :(),
    # :pos         => :(pos = p)
)

sam_record_context = Automa.CodeGenContext(
    generator = :goto,
    checkbounds = false,
    loopunroll = 0
)

sam_record_initcode = quote
    pos = 0
    filled = 0
    found = false
    initialize!(record)
    cs, linenum = state
end

sam_record_loopcode = quote
    if cs < 0
        throw(ArgumentError("malformed SAM file at line $(linenum)"))
    end
    found && @goto __return__
end

sam_record_returncode = quote
    return cs, linenum, found
end

Automa.Stream.generate_reader(
    :readrecord!,
    sam_record_machine,
    arguments = (:(record::Record), :(state::Tuple{Int,Int})),
    actions = sam_record_actions,
    context = sam_record_context,
    initcode = sam_record_initcode,
    loopcode = sam_record_loopcode,
    returncode = sam_record_returncode
) |> eval
