using Dates

import DAQCore: CircMatBuffer
export EnvConds

mutable struct EnvConds{J} <: AbstractJAnem
    devname::String
    devtype::String
    ipaddr::IPv4
    port::Int
    buffer::CircMatBuffer{Float64}
    task::DaqTask
    config::DaqConfig
    chans::DaqChannels{Vector{String}}
    usethread::Bool
    ttot::Float64
    janem::J
end



function EnvConds(devname="EnvConds"; ipaddr="192.168.0.100", port=9525,
                  timeout=10, buflen=10000, tag="", sn="",usethread=true)
    dtype="EnvConds"
    
    buf = CircMatBuffer{Float64}(12,buflen)
    task = DaqTask()
    ch = DaqChannels(["Pa", "H", "T0", "T1", "T2"], 0)
    config = DaqConfig(tag=tag, sn=sn, ip=ipaddr, port=port)
    return EnvConds{Bool}(devname, dtype, IPv4(ipaddr), port, buf, task, config,
                    ch, usethread, 0.0, false)
    
end

function EnvConds(devname="EnvConds", janem::JAnem; 
                  timeout=10, buflen=10000, tag="", sn="",usethread=true)
    dtype="EnvConds"
    
    buf = CircMatBuffer{Float64}(5,buflen)
    task = DaqTask()
    ch = DaqChannels(["Pa", "H", "T0", "T1", "T2"], 0)
    
    return DaqEnvConds{JAnem}(devname, dtype, janem.ipaddr, janem.port, buf, task,
                              janem.config, config, ch, usethread, 0.0, false)
    
end




function DAQCore.daqconfigdev(dev::DaqEnvConds; time=1.0)
    dev.ttot = time
end

function scan!(dev::DaqEnvConds)
    tsk = dev.task
    isreading(tsk) && error("DaqEnvConds is already reading data!")
    cleartask!(tsk)

    buf = dev.buffer
    empty!(buf)
    ttot = Second(dev.ttot)
    
    openjanem(ipaddr(dev), portnum(dev), 5) do io
        tsk.isreading = true
        t1 = now()
        tsk.time = t1

        while(true)
            env = envconds(io)
            b = nextbuffer(buf)
            b .= env
            t2 = now()

            if t2-t1 > ttot
                break
            end
        end
        tsk.isreading = false
    end
        
    
end

function aux_readenvconds(dev)
    
    unit = ["Pa", "", "°C", "°C", "°C"]
    buf = dev.buffer
    Nt = length(buf)
    E = zeros(5, Nt)

    for i in 1:Nt
        E[:,i] .= buf[i]
    end
    t = dev.task.time

    fs = dev.ttot / Nt
    
    sampling = DaqSamplingRate(fs, Nt, dev.task.time)

    return MeasData(devname(dev), devtype(dev), sampling, E, dev.chans, ["V"])
              

end


function DAQCore.daqread(dev::DaqEnvConds)

    wait(dev.task.task)

    aux_readenvconds(dev)
    
end


function DAQCore.daqacquire(dev::DaqEnvConds)

    scan!(dev)
    aux_readenvconds(dev)
end

