using Dates

import DAQCore: CircMatBuffer
export EnvConds

mutable struct EnvConds <: AbstractJAnem
    devname::String
    devtype::String
    ipaddr::IPv4
    port::Int
    task::DaqTask
    buffer::CircMatBuffer{Float64}
    config::DaqConfig
    chans::DaqChannels{Vector{String}}
    usethread::Bool
    ttot::Float64
    temp::Vector{UInt64}
end
    

function EnvConds(devname="EnvConds"; ip="192.168.0.101", port=9525,
                  timeout=10, buflen=10000, tag="", sn="",usethread=true)
    dtype="EnvConds"
    
    task = DaqTask()
    ipaddr = IPv4(ip)
    temp = openjanem(ipaddr, port, 5) do io
        tempchans(io)
    end

    ch1 = ["Pa", "H", "Ta", "Th"]
    for i in eachindex(temp)
        push!(ch1, "T" * string(i-1))
    end
    nch = length(ch1)
    buf = CircMatBuffer{Float64}(nch,buflen)
    
    ch = DaqChannels(ch1, ch1)
    
    config = DaqConfig(tag=tag, sn=sn, ip=ipaddr, port=port)
    return EnvConds(devname, dtype, IPv4(ip), port, task, buf, config,
                    ch, usethread, 0.0, temp)
    
end


    
function DAQCore.daqaddinput(dev::EnvConds, chans; names=nothing)
    avchans = listenvchans(dev)
    
    # Check if  every channel in chans is possible
    for ch in chans
        if ch ∉ avchans
            error("Channel $ch is unknown!")
        end
    end
    if isnothing(names)
        names = chans
    else
        if length(chans) != length(names)
            error("The number of channel names must be equal to the number of channels!")
        end
    end

    chs = [string(ch) for ch in chans]
    chn = [string(ch) for ch in names]
    nn = length(chn)
    bw = bufwidth(dev.buffer)
    if bw != nn
        resize!(dev.buffer, nn, capacity(dev.buffer))
    end
    
    dev.chans = DaqChannels(chs, chn)
    

end

DAQCore.daqchannels(dev::EnvConds) = daqchannels(dev.chans)
DAQCore.numchannels(dev::EnvConds) = numchannels(dev.chans)
DAQCore.physchans(dev::EnvConds) = physchans(dev.chans)


function DAQCore.daqconfigdev(dev::EnvConds; time=1.0)
    dev.ttot = time
end


function readenv(dev::EnvConds)
    openjanem(ipaddr(dev), portnum(dev), 5) do io
        readenv(io, physchans(dev))
    end
end

                
    
function scan!(dev::EnvConds)
    tsk = dev.task
    isreading(tsk) && error("EnvConds is already reading data!")
    cleartask!(tsk)

    buf = dev.buffer
    empty!(buf)
    ttot = Millisecond(ceil(Int, 1000*dev.ttot))
    
    openjanem(ipaddr(dev), portnum(dev), 5) do io
        tsk.isreading = true
        t1 = now()
        tsk.time = t1
        ntries = 0
        while(true)
            try
                env = readenv(io, physchans(dev))
                b = nextbuffer(buf)
                b .= env
                t2 = now()
                tsk.nread += 1
                if t2-t1 > ttot
                    break
                end
                ntries = 0                
            catch e
                ntries = ntries + 1
                if ntries > 4
                    error("Unable to read EnvConds after $ntries")
                end
                
            end
        end
        tsk.isreading = false
    end
        
    
end


const chanunit = Dict{Char,String}('P'=>"Pa", 'H'=>"", 'T'=>"°C")

unitfromchans(ch) = chanunit[ch[1]]


function aux_readenvconds(dev)
    unit = [unitfromchans(ch) for ch in physchans(dev)]
    buf = dev.buffer
    Nt = length(buf)
    E = zeros(numchannels(dev), Nt)

    for i in 1:Nt
        E[:,i] .= buf[i]
    end
    t = dev.task.time

    fs = Nt / dev.ttot 
    
    sampling = DaqSamplingRate(fs, Nt, dev.task.time)

    return MeasData(devname(dev), devtype(dev), sampling, E, dev.chans, ["V"])
              

end

function DAQCore.daqstart(dev::EnvConds)
    if isreading(dev)
        error("Daq already reading!")
    end
    if dev.usethread
        tsk = Threads.@spawn scan!(dev)
    else
        tsk = @async scan!(dev)
    end
    dev.task.task = tsk
    return tsk

end


function DAQCore.daqread(dev::EnvConds)

    wait(dev.task.task)

    aux_readenvconds(dev)
    
end


function DAQCore.daqacquire(dev::EnvConds)

    scan!(dev)
    aux_readenvconds(dev)
end

