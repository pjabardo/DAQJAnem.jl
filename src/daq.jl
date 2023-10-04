# Data acquisition...
using Sockets
using DAQCore
import DataStructures: CircularBuffer

import Dates: now
export DaqJAnem
export devname, devtype, samplingrate, daqconfigdev, daqstart, daqread, daqacquire
export samplingrate, samplingtimes, samplinghours, samplingperiod
export daqaddinput, tempchans, tempchans!, loadtemp!, readchannels

export readpressure, readpressuretemp, readhumidity, readhumiditytemp
export readtemperature, readaichan

abstract type AbstractDaqJAnem <: AbstractInputDev end

@enum JANEM_AQ JANEM_AI JANEM_ENV JANEM_BOTH

mutable struct DaqJAnem <: AbstractDaqJAnem
    devname::String
    devtype::String
    ipaddr::IPv4
    port::Int
    buffer::CircularBuffer{NTuple{5,Int16}}
    task::DaqTask
    config::DaqConfig
    chans::DaqChannels{Vector{Int}}
    usethread::Bool
    ttot::Float64
    temp::Vector{UInt64}
end




"Returns the IP address of the device"
ipaddr(dev::AbstractDaqJAnem) = dev.ipaddr

"Returns the port number used for TCP/IP communication"
portnum(dev::AbstractDaqJAnem) = dev.port

DAQCore.devtype(dev::AbstractDaqJAnem) = "DaqJAnem"

"Is DaqJAnem acquiring data?"
DAQCore.isreading(dev::AbstractDaqJAnem) = isreading(dev.task)

"How many samples have been read?"
DAQCore.samplesread(dev::AbstractDaqJAnem) = samplesread(dev.task)

"Convert number to string justifying to the right by padding with zeros"
numstring(x::Integer, n=2) = string(10^n+x)[2:end]

function Base.show(io::IO, dev::AbstractDaqJAnem)
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

openjanem(dev::AbstractDaqJAnem,  timeout=5) = openjanem(ipaddr(dev), portnum(dev), timeout)


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

function openjanem(fun::Function, dev::AbstractDaqJAnem, timeout=5)
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
    ok = strip(readline(io))
    if ok != "OK"
        err = parse(Int, strip(readline(io)))
        readline(io)
        error("Error setting $var to value $val: code $err")
    end
    return 0
end

function status(dev::AbstractDaqJAnem)
    openjanem(ipaddr(dev), portnum(dev), 1) do io
        status(io)
    end
end

function status(io::TCPSocket)
    println(io, "STATUS")
    sleep(0.1)
    return readline(io)
end
  
    

function DaqJAnem(; devname="Anemometer", ip="192.168.0.100",
                  timeout=10, buflen=100_000, port=9525, tag="", sn="",usethread=true)
    dtype="DaqJAnem"
    ipaddr = IPv4(ip)
    
    openjanem(ipaddr, port, timeout) do io
        setvar(io, "AVG", 1)
        setvar(io, "FPS", 1)
    end

    config = DaqConfig(ip=ip, port=9525, AVG=1, FPS=1)
    buf = CircularBuffer{NTuple{5,Int16}}(buflen)
    task = DaqTask()
    ch = DaqChannels(["E0"], [0])

    temp = openjanem(ipaddr, port, 2) do io
        clearchans(io)
        addsinglechan(io, 0)
        tempchans(io)
    end
    
    return DaqJAnem(devname, dtype, ipaddr, 9525, buf, task, config,
                    ch, usethread, 0.0, temp)
    
end

function clearchans(io::TCPSocket) 
    println(io, "CLEARCHANS")
    s = readline(io)
    if strip(s) != "OK"
        error("Expected 'OK', got $s")
    end
end

clearchans(dev::DaqJAnem, timeout=2) = openjanem(dev,timeout) do io
    clearchans(io)
end

function addsinglechan(io::TCPSocket, ch)
    println(io, "ADDCHAN $ch")
    ok = strip(readline(io))
    if ok != "OK"
        if ok == "ERR"
            err = parse(Int, strip(readline(io)))
            readline(io)
            error("Error adding channel $ch: code $err")
        else
            error("Unknown error while adding channel $ch")
        end
    end
end


function tempchans(io::TCPSocket)
    println(io, "TEMPCHANS")
    readline(io)
    s = strip(readline(io))
    N = parse(Int, s)
    TID = UInt64[]
    for i in 1:N
        s = split(strip(readline(io)))
        id = UInt64(0)
        m = 0
        for sk in s
            k = parse(UInt8, sk)
            id += k << m
            m += 8
        end
        push!(TID, id)
    end
    return TID
end

function tempchans(dev::AbstractDaqJAnem)
    openjanem(dev, 2) do io
        tempchans(io)
    end
end

function tempchans!(dev::AbstractDaqJAnem)
    temp = openjanem(dev, 2) do io
        tempchans(io)
    end
    dev.temp = temp
    temp
end

function loadtemp!(io::TCPSocket)

    println(io, "LOADTEMP")
    readline(io)
    s = strip(readline(io))
    N = parse(Int, s)
    ok = strip(readline(io))
    if ok != "OK"
        error("Error loading DS18B20 temperature sensor info.")
    end
    
end

function readchannels(io::TCPSocket)
    println(io, "CHANS")
    readline(io)
    N = parse(Int, strip(readline(io)))
    chans = zeros(Int, N)
    for i in 1:N
        n1 = parse(Int, strip(readline(io)))
        chans[i] = n1
    end
    return chans
end
readchannels(dev::DaqJAnem, timeout=3) = openjanem(dev, timeout) do io
    readchannels(io)
end

function DAQCore.daqaddinput(dev::DaqJAnem, chans=0; names="E")
    for c in chans
        if c < 0 || c > 3
            error("Channels should be 0-3. Got '$c'")
        end
    end
    if !isa(chans, AbstractVector)
        chans = [chans]
    elseif isa(chans, AbstractVector)
        chans = collect(chans)
    end
    
    # I hope we didn't have any errors
    if names == ""
        chnames = chans .* ""
    elseif isa(names, AbstractString) || isa(names, Symbol) ||
        isa(names, AbstractChar)
        chnames = [string(names) * string(ch) for ch in chans]
    elseif isa(names, AbstractVector)
        chnames = [string(c) for c in names]
    end

    if length(chnames) != length(chans)
        error("'names' should have the same length as 'chans'")
    end
    
    openjanem(dev, 2) do io
        clearchans(io)
        for c in chans
            addsinglechan(io, c)
        end
    end

    dev.chans = DaqChannels(chnames, chans)
    
    
        
end

function DAQCore.daqconfigdev(dev::DaqJAnem; AVG=1, FPS=1)
    openjanem(dev, 3) do io
        setvar(io, "AVG", AVG)
        iparam!(dev.config, "AVG", AVG)
        
        setvar(io, "FPS", FPS)
        iparam!(dev.config, "FPS", FPS)
    end
    
end



function scan!(dev::DaqJAnem) 
    tsk = dev.task
    isreading(tsk) && error("DaqJAnem is already reading data!")
    cleartask!(tsk)

    buf = dev.buffer
    empty!(buf)

    exthrown = false # No exception thrown!

    dev.ttot = 0.0
    openjanem(ipaddr(dev), portnum(dev), 5) do io
        tsk.time = now()
        println(io, "SCAN")
        tsk.isreading = true
        s = readline(io)
        N = parse(Int, s)
        s = readline(io)
        K = parse(Int, s)
        x = zeros(Int16,K) 
        t = 0.0
        for i in 1:N
            try
                s = strip(readline(io))
                ss = split(s)
                idx = parse(Int, ss[1])
                t = parse(Float64, ss[2]) 
                for k in 1:K
                    xi = parse(Int16, ss[k+2])
                    x[k] = xi
                end
                
                tsk.nread += 1
                settiming!(tsk, 0, round(Int64,t*1e9), i)
                dev.ttot = t
                if K == 1
                    push!(buf, (x[1],0,0,0, K))
                elseif K==2
                    push!(buf, (x[1],x[2],0,0, K))
                elseif K==3
                    push!(buf, (x[1],x[2],x[3],0, K))
                else
                    push!(buf, (x[1],x[2],x[3],x[4], K))
                end
                if tsk.stop
                    stopped = true
                    println(io, "!")
                    sleep(0.5)
                    break
                end
            catch e
                tsk.stop = true
                exthrown = true
                if isa(e, InterruptException)
                    # Ctrl-C captured!
                    # We want to stop the data acquisition safely and then rethwrow it!
                    tsk.stop = true
                else
                    throw(e)
                end
            end
            
        end
        tsk.isreading = false
        for k in 1:3
            ok = readline(io)
            if ok == "OK"
                break
            end
            sleep(0.5)
            if k == 3
                error("Expected OK at the end of data acquisition. Got $ok")
            end
            
        end
    end
        
    
end


    
function DAQCore.daqstart(dev::AbstractDaqJAnem)
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


function readaioutput(dev::AbstractDaqJAnem)
    isreading(dev) && error("Still acquiring data!")

    tsk = dev.task
    buf = dev.buffer
    nsamples = length(buf)
    nchans = numchannels(dev.chans)
    E = zeros(nchans,nsamples)
    for (i,x) in enumerate(buf)
        for k in 1:nchans
            E[k,i] =  2.048 * x[k] / 32767
        end
    end
        
    fs = nsamples / dev.ttot

    return E, fs, tsk.time
        
end



function DAQCore.daqread(dev::DaqJAnem)

    wait(dev.task.task)

    E, fs, t = readaioutpuyt(dev)
    unit = "V"
    sampling = DaqSamplingRate(fs, length(E), t)

    return MeasData(devname(dev), devtype(dev), sampling, E, dev.env,
                    dev.chans, ["V"])
              
    
end

function DAQCore.daqacquire(dev::DaqJAnem)

    scan!(dev)
    E, fs, t = readaioutput(dev)
    unit = "V"
    sampling = DaqSamplingRate(fs, length(E), t)
    
    return MeasData(devname(dev), devtype(dev), sampling, E,
                    dev.chans, ["V"])
end






function readcmd(dev::AbstractDaqJAnem, cmd, timeout=5)
    openjanem(ipaddr(dev), portnum(dev), timeout) do io
        x = String[]
        println(io, "READ $cmd")
        s = readline(io)
        if s == "ERR"
            err = parse(Int, strip(readline(io)))
            readline(io)
            error("Rerror reading $cmd: code $err")
        end
        s = readline(io)
        N = parse(Int, s)

        for i in 1:N
            push!(x, readline(io))
        end
        ok = readline(io)
        if ok != "OK"
            error("OK expected. Got $ok!")
        end
        
        x
    end
    
end

readpressure(dev::AbstractDaqJAnem, timeout=1) =
    parse(Float64, readcmd(dev, "P", timeout)[1])

readpressuretemp(dev::AbstractDaqJAnem, timeout=1) =
    parse(Float64, readcmd(dev, "PT", timeout)[1])

readhumidity(dev::AbstractDaqJAnem, timeout=1) =
    parse(Float64, readcmd(dev, "H", timeout)[1])

readhumiditytemp(dev::AbstractDaqJAnem, timeout=1) =
    parse(Float64, readcmd(dev, "HT", timeout)[1])

readtemperature(dev::AbstractDaqJAnem, i=0, timeout=2) =
    parse(Float64, readcmd(dev, "T$i", timeout)[1])

function readaichan(dev::AbstractDaqJAnem, i=0, timeout=2)
    bits = parse(Float64, readcmd(dev, "AI$i", timeout)[1])

    return (bits / 32767) * 2.048
end



