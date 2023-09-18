# Data acquisition...
using Sockets
using DAQCore
import DataStructures: CircularBuffer

import Dates: now
export DaqJAnem
export devname, devtype, samplingrate, daqconfigdev, daqstart, daqread, daqacquire
export samplingrate, samplingtimes, samplinghours, samplingperiod




mutable struct DaqJAnem <: AbstractInputDev
    devname::String
    devtype::String
    ipaddr::IPv4
    port::Int
    buffer::CircularBuffer{NTuple{4,Int16}}
    task::DaqTask
    config::DaqConfig
    chans::DaqChannels{Int}
    usethread::Bool
    ttot::Float64
    env::Matrix{Float64}
end




"Returns the IP address of the device"
ipaddr(dev::DaqJAnem) = dev.ipaddr

"Returns the port number used for TCP/IP communication"
portnum(dev::DaqJAnem) = dev.port

DAQCore.devtype(dev::DaqJAnem) = "DaqJAnem"

"Is DaqJAnem acquiring data?"
DAQCore.isreading(dev::DaqJAnem) = isreading(dev.task)

"How many samples have been read?"
DAQCore.samplesread(dev::DaqJAnem) = samplesread(dev.task)

"Convert number to string justifying to the right by padding with zeros"
numstring(x::Integer, n=2) = string(10^n+x)[2:end]

function Base.show(io::IO, dev::DaqJAnem)
    println(io, "DaqJAnem")
    println(io, "    Dev Name: $(devname(dev))")
    println(io, "    IP: $(string(dev.ipaddr))")
end



function openjanem(ipaddr::IPv4, port=9525,  timeout=5)
        
    sock = TCPSocket()
    t = Timer(_ -> close(sock), timeout)
    try
        connect(sock, ipaddr, port)
    catch e
        if isa(e, InterruptException)
            throw(InterruptException())
        else
            error("Could not connect to $ipaddr ! Turn on the device or set the right IP address!")
        end
    finally
        close(t)
    end
    
    return sock
end

openjanem(dev::DaqJAnem,  timeout=5) = openjanem(ipaddr(dev), portnum(dev), timeout)


function openjanem(fun::Function, ip, port=9525, timeout=5)
    io = openjanem(ip, port, timeout)
    try
        fun(io)
    catch e
        throw(e)
    finally
        close(io)
    end
end

function openjanem(fun::Function, dev::DaqJAnem, timeout=5)
    io = openjanem(ipaddr(dev), portnum(dev), timeout)
    try
        fun(io)
    catch e
        throw(e)
    finally
        close(io)
    end
end

function setvar(io, var, val)
    println(io, "SET $var $val")
    cmd = readline(io)
    ok = readline(io)
    return ok
    
end

function status(dev::DaqJAnem)
    openjanem(ipaddr(dev), portnum(dev), 1) do io
        status(io)
    end
end

function status(io::TCPSocket)
    println(io, "STATUS")
    sleep(0.1)
    return readline(io)
end
  
    

function DaqJAnem(devname="Anemometer", ipaddr="192.168.0.101";
                  timeout=10, buflen=100_000, tag="", sn="",usethread=true)
    dtype="DaqJAnem"
    ip = IPv4(ipaddr)
    port = 9525
    
    openjanem(ip, port, timeout) do io
        setvar(io, "AVG", 1)
        setvar(io, "FPS", 1)
    end

    config = DaqConfig(ip=ipaddr, port=9525, AVG=1, FPS=1)
    buf = CircularBuffer{NTuple{4,Int16}}(buflen)
    task = DaqTask()
    ch = DaqChannels(["E0"], 0)
    env = zeros(Float64,5,2)
    
    return DaqJAnem(devname, dtype, ip, 9525, buf, task, config,
                    ch, usethread, 0.0, env)
    
end


function DAQCore.daqconfigdev(dev::DaqJAnem; AVG=1, FPS=1)
    openjanem(ipaddr(dev), portnum(dev), 1) do io
        ok = setvar(io, "AVG", AVG)
        if ok != "OK"
            error("Error in `SET AVG $AVG`")
        else
            iparam!(dev.config, "AVG", AVG)
        end
        
        ok = setvar(io, "FPS", FPS)
        if ok != "OK"
            error("Error in `SET FPS $FPS`")
        else
            iparam!(dev.config, "FPS", FPS)

        end
    end
    
end


function envconds(io::TCPSocket)

    println(io, "ENV")
    s = readline(io)
    N = parse(Int, s)

    x = Float64[]
    for i in 1:N
        s = readline(io)
        xi = parse(Float64,s)
        push!(x, xi)
    end
    ok = readline(io)
    if ok != "OK"
        error("Sometinh went wrong when reading env conds -> $ok")
    end

    return x
end

envconds(dev::DaqJAnem) =  openjanem(ipaddr(dev), portnum(dev), 5) do io
    envconds(io)
end


function scan!(dev::DaqJAnem) 
    tsk = dev.task
    isreading(tsk) && error("DaqJAnem is already reading data!")
    cleartask!(tsk)

    buf = dev.buffer
    empty!(buf)
    
    dev.ttot = 0.0
    openjanem(ipaddr(dev), portnum(dev), 5) do io
        dev.env[:,1] .= envconds(io)
        tsk.time = now()
        println(io, "SCAN")
        tsk.isreading = true
        s = readline(io)
        N = parse(Int, s)
        s = readline(io)
        K = parse(Int, s)
        x = zeros(Int16,K) 
        t0 = time_ns()
        for i in 1:N
            for k in 1:K
                s = readline(io)
                xi = parse(Int16, s)
                x[k] = xi
            end
            tn = time_ns()
            tsk.nread += 1
            settiming!(tsk, t0, tn, i)
            dev.ttot = (tn-t0) / 1e9
            push!(buf, (x[1],0,0,0))
        end
        s = readline(io)
        ttot = parse(Float64, s)
        dev.ttot = ttot
        ok = readline(io)
        tsk.isreading = false
        if ok != "OK"
            error("Expected OK at the end of data acquisition. Got $ok")
        end
        dev.env[:,2] .= envconds(io)
    end
        
    
end


    
function DAQCore.daqstart(dev::DaqJAnem)
    if isreading(dev)
        error("DaqJAnem already reading!")
    end
    if dev.usethread
        tsk = Threads.@spawn scan!(dev)
    else
        tsk = @async scan!(dev)
    end
    dev.task.task = tsk
    return tsk
    
end


function readaioutput(dev::DaqJAnem)
    isreading(dev) && error("Still acquiring data!")

    tsk = dev.task
    buf = dev.buffer
    nsamples = length(buf)
    E = zeros(1,nsamples)
    for (i,x) in enumerate(buf)
        E[1,i] = 2.048 * x[1] / 32768
    end
        
    fs = nsamples / dev.ttot

    return E, fs, tsk.time
        
end


mutable struct AnemData{T,AT<:AbstractMatrix{T},ET<:AbstractMatrix{T},
                        S<:AbstractDaqSampling,CH} <: DAQCore.AbstractMeasData
    "Device that generated the data"
    devname::String
    "Type of device"
    devtype::String
    "Sampling timing data"
    sampling::S
    "Data acquired"
    data::AT
    "Environmental conditions"
    env::ET
    "Channel Information"
    chans::CH
    "Units of each channel"
    units::Vector{String}
end



function DAQCore.daqread(dev::DaqJAnem)

    wait(dev.task.task)

    E, fs, t = readaioutpuyt(dev)
    unit = "V"
    sampling = DaqSamplingRate(fs, length(E), t)

    return AnemData(devname(dev), devtype(dev), sampling, E, dev.env,
                    dev.chans, ["V"])
              
    
end

function DAQCore.daqacquire(dev::DaqJAnem)

    scan!(dev)
    E, fs, t = readaioutput(dev)
    unit = "V"
    sampling = DaqSamplingRate(fs, length(E), t)
    
    return AnemData(devname(dev), devtype(dev), sampling, E, dev.env,
                    dev.chans, ["V"])
end





"What was the sampling rate of the data acquisition?"
samplingrate(d::AnemData) = samplingrate(d.sampling)
samplingtimes(d::AnemData) = samplingtimes(d.sampling)
samplinghours(d::AnemData) = samplinghours(d.sampling)
samplingperiod(d::AnemData) = samplingperiod(d.sampling)
daqtime(d::AnemData) = daqtime(d.sampling)

"Access to the data acquired"
measdata(d::AnemData) = d.data
daqchannels(d::AnemData) = daqchannels(d.chans)
numchannels(d::AnemData) = numchannels(d.chans)
