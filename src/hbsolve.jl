
"""

    hbsolve()

"""

function hbsolve(ws,wp,Ip,Nsignalmodes,Npumpmodes,circuit,circuitdefs; pumpports=[1],
    solver =:klu, iterations=100,symfreqvar=nothing,
    nbatches = Base.Threads.nthreads(), sorting=:number)

    # parse and sort the circuit
    psc = parsesortcircuit(circuit,sorting=sorting)

    # calculate the circuit graph
    cg = calccircuitgraph(psc)

    # solve the nonlinear system    
    pump=hbnlsolve(wp,Ip,Npumpmodes,psc,cg,circuitdefs,ports=pumpports,
        solver=solver,iterations=iterations, symfreqvar=symfreqvar)

    # the node flux
    phin = pump.out.zero

    # convert from node flux to branch flux
    phib = pump.Rbnm*phin

    # calculate the sine and cosine nonlinearities from the pump flux
    Am = sincosnloddtoboth(phib[pump.Ljbm.nzind],length(pump.Ljb.nzind),pump.Nmodes)

    # solve the linear system
    signal=hblinsolve(ws,psc,cg,circuitdefs,wp=wp,Nmodes=Nsignalmodes,
        Am=Am,solver=solver,symfreqvar=symfreqvar,nbatches = nbatches)

    return HB(pump,Am,signal)
end

struct HB
    pump
    Am
    signal
end


"""

    hblinsolve(w,wp,Nmodes,circuit,circuitdefs,Am)

"""
function hblinsolve(w,circuit,circuitdefs;wp=0,Nmodes=1,Am=zeros(Complex{Float64},0,0),
    solver=:klu,symfreqvar=nothing, nbatches = Base.Threads.nthreads(), sorting=:number)

    # parse and sort the circuit
    psc = parsesortcircuit(circuit,sorting=sorting)

    # calculate the circuit graph
    cg = calccircuitgraph(psc)

    return hblinsolve(w,psc,cg,circuitdefs;wp=wp,Nmodes=Nmodes,Am=Am,
        solver=solver,symfreqvar=symfreqvar, nbatches = nbatches)

end

function hblinsolve(w,psc::ParsedSortedCircuit,cg::CircuitGraph,
    circuitdefs;wp=0,Nmodes=1,Am=zeros(Complex{Float64},0,0),
    solver=:klu,symfreqvar=nothing, nbatches = Base.Threads.nthreads())


    # calculate the numeric matrices
    nm=numericmatrices(psc,cg,circuitdefs,Nmodes=Nmodes)

    # extract the elements we need
    Nnodes = psc.Nnodes
    Nbranches = cg.Nbranches
    edge2indexdict = cg.edge2indexdict
    Ljb = nm.Ljb
    Rbnm = nm.Rbnm
    Cnm = nm.Cnm
    Gnm = nm.Gnm
    invLnm = nm.invLnm
    portdict = nm.portdict
    resistordict = nm.resistordict

    # generate the mode indices and find the signal index
    indices = calcindices(Nmodes)
    signalindex = findall(indices .== 0)[1]

    # if Am is undefined, define it. 
    if length(Am) == 0
        Am = zeros(Complex{Float64},2*Nmodes,length(Ljb.nzval))

        Am[1,:] .= 1.0
    end

    # calculate AoLjbm, the sparse branch AoLj matrix
    AoLjbm = calcAoLjbm(Am,Ljb,1,Nmodes,Nbranches)

    # convert to a sparse node matrix
    AoLjnm = transpose(Rbnm)*AoLjbm*Rbnm

    # calculate the source currents
    Nports = length(portdict)

    # calculate the source terms in the branch basis
    bbm = zeros(Complex{Float64},Nbranches*Nmodes,Nmodes*Nports)

    sortindices = sortperm(collect(values(portdict)))
    sortedkeys = collect(keys(portdict))[sortindices]
    i=1
    for key in sortedkeys
        for j = 1:Nmodes
            bbm[(edge2indexdict[key]-1)*Nmodes+j,(i-1)*Nmodes+j] = 1
            # bbm2[(i-1)*Nmodes+j,(i-1)*Nmodes+j] = Lmean*1/phi0
        end
        i+=1
    end

    # calculate the source terms in the node basis
    bnm = transpose(Rbnm)*bbm

    # make empty matrices for the voltages, node fluxes, and scattering parameters
    voltages = zeros(Complex{Float64},Nmodes*(Nnodes-1),Nmodes*Nports,length(w))
    # phin = zeros(Complex{Float64},Nmodes*(Nnodes-1),Nmodes*Nports)
    S = zeros(Complex{Float64},Nports*Nmodes,Nports*Nmodes,length(w))

    # as a test don't save voltages and node fluxes
    # voltages = Vector{Complex{Float64}}(undef,0)
    phin = Vector{Complex{Float64}}(undef,0)


    # find the indices at which there are symbolic variables so we can
    # perform a substitution on only those. 
    Cnmfreqsubstindices  = symbolicindices(Cnm)
    Gnmfreqsubstindices  = symbolicindices(Gnm)
    invLnmfreqsubstindices  = symbolicindices(invLnm)

    # drop any zeros in AoLjnm
    dropzeros!(AoLjnm)
    # make something with the same shape as A so we can find the sparsity
    # pattern. substitute in the symbolic variables for this addition. 
    wmodes = calcw(w[1],indices,wp);
    Cnmcopy = freqsubst(Cnm,wmodes,symfreqvar)
    Gnmcopy = freqsubst(Gnm,wmodes,symfreqvar)
    invLnmcopy = freqsubst(invLnm,wmodes,symfreqvar)
    Asparse = (AoLjnm + invLnmcopy + Gnmcopy + Cnmcopy)

    # make the index maps so we can efficiently add the sparse matrices
    # together without allocations or changing the sparsity structure. 
    Cnmindexmap = sparseaddmap(Asparse,Cnmcopy)
    Gnmindexmap = sparseaddmap(Asparse,Gnmcopy)
    invLnmindexmap = sparseaddmap(Asparse,invLnmcopy)
    AoLjnmindexmap = sparseaddmap(Asparse,AoLjnm)

    # solve the linear system for the specified frequencies
    # the response for each frequency is independent so it can be done in
    # parallel; however we want to reuse the factorization object and other
    # input arrays. perform array allocations and factorization "nbatches"
    # times and let FLoops decide how many threads to spawn and schedule.
    # nbatches will put a cap on the number of threads.


    # conj!(AoLjnm.nzval)

    ### single threaded
    if nbatches == 1

        hblinsolve_inner!(S,voltages,Asparse,AoLjnm,invLnm,
                Cnm,Gnm,bnm,AoLjnmindexmap,invLnmindexmap,Cnmindexmap,Gnmindexmap,
                Cnmfreqsubstindices,Gnmfreqsubstindices,invLnmfreqsubstindices,
                portdict,resistordict,w,indices,wp,Nports,Nmodes,Nnodes,solver,
                symfreqvar,1:length(w))
    else

        # ### parallel using floop. i like floop because it supports the partition
        # ### iterator. 
        # @floop for wi in Base.Iterators.partition(1:length(w),length(w)÷nbatches)
        #    hblinsolve_inner!(S,voltages,Asparse,AoLjnm,invLnm,
        #         Cnm,Gnm,bnm,AoLjnmindexmap,invLnmindexmap,Cnmindexmap,Gnmindexmap,
        #         portdict,resistordict,w,indices,wp,Nports,Nmodes,Nnodes,solver,
        #         symfreqvar,wi)
        # end

        ### parallel using native threading
        @sync for wi in Base.Iterators.partition(1:length(w),1+(length(w)-1)÷nbatches)
            Base.Threads.@spawn hblinsolve_inner!(S,voltages,Asparse,AoLjnm,
                invLnm,Cnm,Gnm,bnm,
                AoLjnmindexmap,invLnmindexmap,Cnmindexmap,Gnmindexmap,
                Cnmfreqsubstindices,Gnmfreqsubstindices,invLnmfreqsubstindices,
                portdict,resistordict,w,indices,wp,Nports,Nmodes,Nnodes,solver,
                symfreqvar,wi)
        end

    end

    return LinearHB(S, Nmodes,voltages,phin,Nnodes,Nbranches,signalindex,w)

end


function hblinsolve_inner!(S,voltages,Asparse,AoLjnm,
    invLnm,Cnm,Gnm,bnm,
    AoLjnmindexmap,invLnmindexmap,Cnmindexmap,Gnmindexmap,
    Cnmfreqsubstindices,Gnmfreqsubstindices,invLnmfreqsubstindices,portdict,
    resistordict,w,indices,wp,
    Nports,Nmodes,Nnodes,solver,
    symfreqvar,wi)

    input = Diagonal(zeros(Complex{Float64},Nports*Nmodes))
    output = zeros(Complex{Float64},Nports*Nmodes,Nports*Nmodes)
    phibports = zeros(Complex{Float64},Nports*Nmodes,Nports*Nmodes)
    phin = zeros(Complex{Float64},Nmodes*(Nnodes-1),Nmodes*Nports)

    # operate on a copy of Asparse because it may be modified by multiple threads
    # at the same time. 
    Asparsecopy = copy(Asparse)


    #if banded=true, then calculate the bandwidths and convert the matrices to 
    # banded matrices. 
    if solver == :banded
        # (lb,ub) = calcbandwidths(AoLjnm,m.invLnm,m.Cnm,m.Gnm)
        (lb,ub) = calcbandwidths(AoLjnm,invLnm,Cnm,Gnm)
        Abanded = BandedMatrix(AoLjnm,(lb,ub))

    elseif solver ==:klu
        # if using the KLU factorization and sparse solver then make a 
        # factorization for the sparsity pattern. 
        F = KLU.klu(Asparse)
    else
        error("Error: Unknown solver")
    end

    for i in wi

        ws = w[i]
        wmodes = calcw(ws,indices,wp);
        wmodesm = Diagonal(repeat(wmodes,outer=Nnodes-1));
        wmodes2m = Diagonal(repeat(wmodes.^2,outer=Nnodes-1));

        # perform the operation below in a way that doesn't allocate significant
        # memory, plus take the conjugates mentioned below. 
        # A = (AoLjnm + invLnm - im.*Gnm*wmodesm - Cnm*wmodes2m)

        fill!(Asparsecopy.nzval,zero(eltype(Asparsecopy.nzval)))
        sparseadd!(Asparsecopy,1,AoLjnm,AoLjnmindexmap)

        # take the complex conjugate of the negative frequency terms in
        # the capacitance and conductance matrices. substitute in the symbolic
        # frequency variable if present. 
        sparseaddconjsubst!(Asparsecopy,-1,Cnm,wmodes2m,Cnmindexmap,
            wmodesm .< 0,wmodesm,Cnmfreqsubstindices,symfreqvar)
        sparseaddconjsubst!(Asparsecopy,im,Gnm,wmodesm,Gnmindexmap,
            wmodesm .< 0,wmodesm,Gnmfreqsubstindices,symfreqvar)
        sparseaddconjsubst!(Asparsecopy,1,invLnm,Diagonal(ones(size(invLnm,1))),invLnmindexmap,
            wmodesm .< 0,wmodesm,invLnmfreqsubstindices,symfreqvar)


        # solve the linear system
        if solver == :banded

            fill!(Abanded,0)
            sparsetobanded!(Abanded,Asparsecopy)

            # # phin = A \ bnm
            ldiv!(phin,Abanded,bnm)
        elseif solver == :klu
            # update the factorization. the sparsity structure does not change
            # so we can reuse the factorization object.
            KLU.klu!(F,Asparsecopy)

            # solve the linear system
            # phin = klu(A) \ bnm
            ldiv!(phin,F,bnm)
        else
            error("Error: Unknown solver")
        end

        # convert to node voltages. node flux is defined as the time integral of 
        # node voltage so node voltage is derivative of node flux which can be
        # accomplished in the frequency domain by multiplying by j*w.
        voltages[:,:,i] = im*wmodesm*phin

        # calculate the branch fluxes
        calcphibports!(phibports,phin,portdict,Nmodes)

        # it seems weird i am defining Ip here. i should be taking it from
        # bbm. 

        # calculate the input and output voltage waves at each port
        calcinput!(input,1.0,phibports,portdict,resistordict,wmodes,symfreqvar)
        calcoutput!(output,phibports,portdict,resistordict,wmodes,symfreqvar)

        # calculate the scattering parameters
        calcS!(view(S,:,:,i),input,output)
    end
    return nothing
end

struct LinearHB
    S
    Nmodes
    v
    phin
    Nnodes
    Nbranches
    signalindex
    w
end



"""
    hbnlsolve(wp,Ip,Nmodes,circuit,circuitdefs)

I should make it so i can easily sweep pump frequency and pump current
without parsing this again. at the very least i should define this
so that i can pass in the already parsed circuit and already generated
numeric matrices.

"""

function hbnlsolve(wp,Ip,Nmodes,circuit,circuitdefs;ports=[1],solver=:klu,
    iterations=100,symfreqvar=nothing, sorting=:number)

    # parse and sort the circuit
    psc = parsesortcircuit(circuit,sorting=sorting)

    # calculate the circuit graph
    cg = calccircuitgraph(psc)

    return hbnlsolve(wp,Ip,Nmodes,psc,cg,circuitdefs;ports=ports,
        solver=solver,iterations=iterations,symfreqvar=symfreqvar)

end

function hbnlsolve(wp,Ip,Nmodes,psc::ParsedSortedCircuit,cg::CircuitGraph,
    circuitdefs;ports=[1],solver=:klu,iterations=100,symfreqvar=nothing)


    # calculate the numeric matrices
    nm=numericmatrices(psc,cg,circuitdefs,Nmodes=Nmodes)

    # extract the elements we need
    Nnodes = psc.Nnodes
    Nbranches = cg.Nbranches
    edge2indexdict = cg.edge2indexdict
    Ljb = nm.Ljb
    Ljbm = nm.Ljbm
    Rbnm = nm.Rbnm
    Cnm = nm.Cnm
    Gnm = nm.Gnm
    invLnm = nm.invLnm
    portdict = nm.portdict
    resistordict = nm.resistordict
    Lmean = nm.Lmean
    # Lmean = 1.0
    Lb = nm.Lb

    # generate the pump frequencies
    # odd harmonics of the pump
    wmodes = zeros(Float64,Nmodes)
    for i = 1:Nmodes
        wmodes[i]=wp*(1 + 2*(i-1))
    end
    wmodesm = Diagonal(repeat(wmodes,outer=Nnodes-1))
    wmodes2m = Diagonal(repeat(wmodes.^2,outer=Nnodes-1))


    # # i need to do the current sources correctly. 
    # bm = zeros(Complex{Float64},(Nnodes-1)*Nmodes)
    # bm[1] = Ip*Lmean/phi0

    # calculate the source terms in the branch basis
    bbm = zeros(Complex{Float64},Nbranches*Nmodes)    


    sortindices = sortperm(collect(values(portdict)))
    sortedkeys = collect(keys(portdict))[sortindices]
    for key in sortedkeys
    # for (key,val) in sort(collect(portdict), by=x->real(x[2]))
        # if val in ports
        if portdict[key] in ports
          bbm[(edge2indexdict[key]-1)*Nmodes+1] = Lmean*Ip/phi0
        end
    end

    # convert from the node basis to the branch basis
    bnm = transpose(Rbnm)*bbm

    # define a random initial value for Am so we can get the sparsity structure of
    # the Jacobian. 
    Am = rand(Complex{Float64},2*Nmodes,length(Ljb.nzval))

    # calculate AoLjbm, the sparse branch AoLj matrix
    AoLjbm = calcAoLjbm(Am,Ljb,Lmean,Nmodes,Nbranches)
    AoLjbmcopy = calcAoLjbm(Am,Ljb,Lmean,Nmodes,Nbranches)

    # convert to a sparse node matrix. Note: I was having problems with type 
    # instability when i used AoLjbm here instead of AoLjbmcopy. 
    AoLjnm = transpose(Rbnm)*AoLjbmcopy*Rbnm;

    # define arrays of zeros for the function
    x = zeros(Complex{Float64},(Nnodes-1)*Nmodes)
    F = zeros(Complex{Float64},(Nnodes-1)*Nmodes)
    AoLjbmvector = zeros(Complex{Float64},Nbranches*Nmodes)

    # make a sparse transpose (improves multiplication speed slightly)
    Rbnmt = sparse(transpose(Rbnm))

    # substitute in the symbolic variables
    Cnm = freqsubst(Cnm,wmodes,symfreqvar)
    Gnm = freqsubst(Gnm,wmodes,symfreqvar)
    invLnm = freqsubst(invLnm,wmodes,symfreqvar)

    # scale the matrices for numerical reasons
    Cnm *= Lmean
    Gnm *= Lmean
    invLnm *= Lmean

    # calculate the structure of the Jacobian
    Jsparse = (AoLjnm + invLnm - im*Gnm*wmodesm - Cnm*wmodes2m)

    # make the index maps so we can efficiently add the sparse matrices 
    # together
    AoLjnmindexmap = sparseaddmap(Jsparse,AoLjnm)
    invLnmindexmap = sparseaddmap(Jsparse,invLnm)
    Gnmindexmap = sparseaddmap(Jsparse,Gnm)
    Cnmindexmap = sparseaddmap(Jsparse,Cnm)


    function FJsparse!(F,J,x)
        calcfj!(F,J,x,wmodesm,wmodes2m,Rbnm,Rbnmt,invLnm,Cnm,Gnm,bnm,
        Ljb,Ljbm,Nmodes,
        Nbranches,Lmean,AoLjbmvector,AoLjbm,
        AoLjnmindexmap,invLnmindexmap,Gnmindexmap,Cnmindexmap)
        return F,J
    end

    # calculate the structure of the Jacobian, depending on the solver type
    if solver == :banded
        (lb,ub) = calcbandwidths(AoLjnm,invLnm,Cnm,Gnm)
        Jbanded = BandedMatrix(Jsparse,(lb,ub))

        odbanded = NLsolve.OnceDifferentiable(NLsolve.only_fj!(FJsparse!),x,F,Jbanded)

        # use the default solver for banded matrices
        out=NLsolve.nlsolve(odbanded,method = :trust_region,autoscale=false,x,iterations=iterations,linsolve=(x, A, b) ->ldiv!(x,A,b))

    elseif solver == :klu

        # perform a factorization. this will be updated later for each 
        # interation
        FK = KLU.klu(Jsparse)

        odsparse = NLsolve.OnceDifferentiable(NLsolve.only_fj!(FJsparse!),x,F,Jsparse)

        # if the sparsity structure doesn't change, we can cache the 
        # factorization. this is a significant speed improvement.
        out=NLsolve.nlsolve(odsparse,method = :trust_region,autoscale=false,x,iterations=iterations,linsolve=(x, A, b) ->(KLU.klu!(FK,A);ldiv!(x,FK,b)) )
    else
        error("Error: Unknown solver")
    end

    if out.f_converged == false
        println("Nonlinear solver not converged. You may need to supply a better
        guess at the solution vector, increase the number of pump harmonics, or
        increase the number of iterations.")
    end

    # calculate the scattering parameters for the pump
    # Nports = length(cdict[:P])
    Nports = length(portdict)
    # input = zeros(Complex{Float64},Nports*Nmodes)
    input = Diagonal(zeros(Complex{Float64},Nports*Nmodes))

    output = zeros(Complex{Float64},Nports*Nmodes)
    phibports = zeros(Complex{Float64},Nports*Nmodes)
    inputval = zero(Complex{Float64})
    S = zeros(Complex{Float64},Nports*Nmodes,Nports*Nmodes)

    phin = out.zero

    # calculate the branch fluxes
    calcphibports!(phibports,phin,portdict,Nmodes)

    # calculate the input and output voltage waves at each port
    calcinput!(input,Ip/phi0,phibports,portdict,resistordict,wmodes,symfreqvar)
    calcoutput!(output,phibports,portdict,resistordict,wmodes,symfreqvar)

    # calculate the scattering parameters
    # calcS!(S,input,output,phibports,portdict,resistordict,wmodes)

    if Ip > 0
        calcS!(S,input,output)
    end

    return NonlinearHB(out,phin,Rbnm,Ljb,Lb,Ljbm,Nmodes,Nbranches,S)

end

struct NonlinearHB
    out
    phin
    Rbnm
    Ljb
    Lb
    Ljbm
    Nmodes
    Nbranches
    S
end


"""
    calcfj(F,J,phin,wmodesm,wmodes2m,Rbnm,invLnm,Cnm,Gnm,bm,Ljb,Ljbindices,
        Ljbindicesm,Nmodes,Lmean,AoLjbm)
        
Calculate the residual and the Jacobian. These are calculated with one function
in order to reuse the time domain nonlinearity calculation.

Leave off the type signatures on F and J because the solver will pass a type of
Nothing if it only wants to calculate F or J. 

"""
function calcfj!(F,
        J,
        phin::AbstractVector,
        wmodesm::AbstractMatrix, 
        wmodes2m::AbstractMatrix, 
        Rbnm::AbstractArray{Int64,2}, 
        Rbnmt::AbstractArray{Int64,2}, 
        invLnm::AbstractMatrix, 
        Cnm::AbstractMatrix, 
        Gnm::AbstractMatrix, 
        bnm::AbstractVector, 
        Ljb::SparseVector, 
        Ljbm::SparseVector,
        Nmodes::Int64, 
        Nbranches::Int64,
        Lmean,
        AoLjbmvector::AbstractVector,
        AoLjbm,AoLjnmindexmap,invLnmindexmap,Gnmindexmap,Cnmindexmap)

    # convert from a node flux to a branch flux
    phib = Rbnm*phin

    # calculate the sine and cosine nonlinearities 
    # println("fft")
    # @time 
    Am = sincosnloddtoboth(phib[Ljbm.nzind],nnz(Ljb),Nmodes)

    # calculate the residual
    # println("F")
    # @time 
    if !(F == nothing)

        # calculate the function. use the sine terms. Am[2:2:2*Nmodes,:]
        # calculate  AoLjbm, this is just a diagonal matrix. 
        # check if this is consistent with other calculations
        @inbounds for i = 1:nnz(Ljb)
            for j = 1:Nmodes
                AoLjbmvector[(Ljb.nzind[i]-1)*Nmodes + j] = Am[2*j,i]*(Lmean/Ljb.nzval[i])

            end
        end

        F .= Rbnmt*AoLjbmvector + (invLnm + im*Gnm*wmodesm - Cnm*wmodes2m)*phin - bnm
    end

    #calculate the Jacobian
    # println("J")
    # @time 
    if !(J == nothing)

        # calculate  AoLjbm
        updateAoLjbm!(AoLjbm,Am,Ljb,Lmean,Nmodes,Nbranches)

        # convert to a sparse node matrix
        # println("AoLjnm")
        # @time 
        AoLjnm = Rbnmt*AoLjbm*Rbnm


        # if isbanded(J)

        if typeof(J) == BandedMatrix{ComplexF64, Matrix{ComplexF64}, Base.OneTo{Int64}}

            # calculate the Jacobian. Convert to a banded matrix if J is banded. 
            # J .= BandedMatrix(AoLjnm + invLnm - im*Gnm*wmodesm - Cnm*wmodes2m)
            # the code below converts the sparse matrices into banded matrices
            # with minimal memory allocations. this is a significant speed
            # improvement. 
            fill!(J,0)
            sparsetobanded!(J,AoLjnm)
            bandedsparseadd!(J,invLnm)
            bandedsparseadd!(J,im,Gnm,wmodesm)
            bandedsparseadd!(J,-1,Cnm,wmodes2m)
        else
            # calculate the Jacobian. If J is sparse, keep it sparse. 
            # @time J .= AoLjnm .+ invLnm .- im.*Gnm*wmodesm .- Cnm*wmodes2m
            # the code below adds the sparse matrices together with minimal
            # memory allocations and without changing the sparsity structure.
            fill!(J,0)
            sparseadd!(J,AoLjnm,AoLjnmindexmap)
            sparseadd!(J,invLnm,invLnmindexmap)
            sparseadd!(J,im,Gnm,wmodesm,Gnmindexmap)
            sparseadd!(J,-1,Cnm,wmodes2m,Cnmindexmap)
        end
    end
    return nothing
end


"""
    calcAoLjbm(Am,Ljb::SparseVector,Lmean,Nmodes,Nbranches)



# Examples
```jldoctest
julia> @syms Lj1 Lj2 A11 A12 A21 A22 A31 A32;JosephsonCircuits.calcAoLjbm([A11;A21;A31],sparsevec([1],[Lj1]),1,2,1)
2×2 SparseMatrixCSC{Any, Int64} with 4 stored entries:
 A11 / Lj1  conj(A31 / Lj1)
 A31 / Lj1  A11 / Lj1

julia> @syms Lj1 Lj2 A11 A12 A21 A22 A31 A32;JosephsonCircuits.calcAoLjbm([A11 A12;A21 A22;A31 A32],sparsevec([1,2],[Lj1,Lj2]),1,2,2)
4×4 SparseMatrixCSC{Any, Int64} with 8 stored entries:
  A11 / Lj1   conj(A31 / Lj1)  ⋅           ⋅
  A31 / Lj1   A11 / Lj1        ⋅           ⋅
 ⋅           ⋅                  A12 / Lj2   conj(A32 / Lj2)
 ⋅           ⋅                  A32 / Lj2   A12 / Lj2
```
"""
function calcAoLjbm(Am,Ljb::SparseVector,Lmean,Nmodes,Nbranches)

    # define empty vectors for the rows, columns, and values
    I = Vector{eltype(Ljb.nzind)}(undef,nnz(Ljb)*Nmodes^2)
    J = Vector{eltype(Ljb.nzind)}(undef,nnz(Ljb)*Nmodes^2)

    type = promote_type(eltype(Am),eltype(1 ./Ljb.nzval))

    if type <: Symbolic
        type = Any
    end

    V = Vector{type}(undef,nnz(Ljb)*Nmodes^2)


    if size(Am,2) != nnz(Ljb)
        throw(DimensionError("The second axis of Am must equal the number of nonzero elements in Ljb (the number of JJs)."))
    end

    if length(Ljb) > Nbranches
        throw(DimensionError("The length of Ljb cannot be larger than the number of branches."))
    end

    # calculate  AoLjbm
    n = 1
    for i = 1:nnz(Ljb)
        for j = 1:Nmodes
            for k = 1:Nmodes

                # calculate the toeplitz matrices for each node 
                I[n]=j+(Ljb.nzind[i]-1)*Nmodes
                J[n]=k+(Ljb.nzind[i]-1)*Nmodes

                # assume terms we don't have pump data for are zero.
                index = 2*abs(j-k)+1
                if index > size(Am,1)
                    V[n] = 0
                else
                    V[n]=Am[index,i]*(Lmean/Ljb.nzval[i])
                end

                #take the complex conjugate of the upper half (not the diagonal)
                if j-k<0
                    V[n] = conj(V[n])
                end

                ## for debugging. calculate index, Ljb.nzind and i from I and J.
                # println("index: ",index," ", 2*abs(I[n]-J[n])+1)
                # println("Ljb.nzind: ",Ljb.nzind[i]," ", ((I[n]+J[n]-1) ÷ (2*Nmodes))+1)
                # println("i: ",i," ", searchsortedfirst(Ljb.nzind,((I[n]+J[n]-1) ÷ (2*Nmodes))+1))
                # println("j: ",j," ",I[n]-(Ljb.nzind[i]-1)*Nmodes," k: ",k," ",J[n]-(Ljb.nzind[i]-1)*Nmodes)

                n+=1
            end
        end
    end

    # assemble the sparse branch AoLj matrix
    return sparse(I,J,V,Nbranches*Nmodes,Nbranches*Nmodes)
end


"""
    updateAoLjbm!(AoLjbm::SparseMatrixCSC,Am,Ljb::SparseVector,Lmean,Nmodes,Nbranches)

# Examples
```jldoctest
@syms Lj1 Lj2 A11 A12 A21 A22 A31 A32;
AoLjbm = JosephsonCircuits.calcAoLjbm([A11 A12;A21 A22;A31 A32],sparsevec([1,2],[Lj1,Lj2]),1,2,2);
AoLjbmcopy = copy(AoLjbm);
AoLjbmcopy.nzval .= 0;
JosephsonCircuits.updateAoLjbm!(AoLjbmcopy,[A11 A12;A21 A22;A31 A32],sparsevec([1,2],[Lj1,Lj2]),1,2,2)
all(AoLjbmcopy.nzval .- AoLjbm.nzval .== 0)

# output
true
```
"""
function updateAoLjbm!(AoLjbm::SparseMatrixCSC,Am,Ljb::SparseVector,Lmean,Nmodes,Nbranches)

    # check that there are the right number of nonzero values. 
    # check that the dimensions are consistent with Nmode and Nbranches.

    if nnz(Ljb)*Nmodes^2 != nnz(AoLjbm)
        throw(DimensionError("The number of nonzero elements in AoLjbm are not consistent with nnz(Ljb) and Nmodes."))
    end

    if size(Am,2) != nnz(Ljb)
        throw(DimensionError("The second axis of Am must equal the number of nonzero elements in Ljb (the number of JJs)."))
    end

    if length(Ljb) > Nbranches
        throw(DimensionError("The length of Ljb cannot be larger than the number of branches."))
    end

    # i want a vector length(Ljb) where the indices are the values Ljb.nzind
    # and the values are the indices of Ljb.nzind
    indexconvert = zeros(Int64,length(Ljb))
    for (i,j) in enumerate(Ljb.nzind)
        indexconvert[j] = i
    end


    for l = 1:length(AoLjbm.colptr)-1
        for m in AoLjbm.colptr[l]:(AoLjbm.colptr[l+1]-1)

            i = indexconvert[((AoLjbm.rowval[m]+l-1) ÷ (2*Nmodes))+1]
            index = 2*abs(AoLjbm.rowval[m]-l)+1

            if index > size(Am,1)
                AoLjbm.nzval[m] = 0
            else
                AoLjbm.nzval[m]=Am[index,i]*(Lmean/Ljb.nzval[i])
            end

            #take the complex conjugate of the upper half (not the diagonal)
            if AoLjbm.rowval[m]-l<0
                AoLjbm.nzval[m] = conj(AoLjbm.nzval[m])
            end

        end
    end

    return nothing
end


"""
    sincosnloddtoboth(amodd::Array{Complex{Float64},1},Nbranches::Int64,m::Int64)

Applies the junction nonlinearity to a vector of branch fluxes of length Nbranches*m
where m is the number of odd pump harmonics (1w, 3w, 5w, etc). The ordering is 
(mode 1, node 1), (mode 2, node 1) ... (mode 1, node 2) ... Returns even AND
odd terms in a 2d array with dimensions 2*m by Nbranches. 

# Examples
```
julia> JosephsonCircuits.sincosnloddtoboth([0.5+0.0im,0,0,0],1,4)
8×1 Matrix{ComplexF64}:
      0.765197686557965 + 0.0im
    0.44005058574495276 + 0.0im
   -0.11490348493140044 + 0.0im
    -0.0195633539946485 + 0.0im
  0.0024766387010484933 - 0.0im
  0.0002497629794613717 + 0.0im
  -2.084411456060309e-5 + 0.0im
 -3.0046516347986037e-6 + 0.0im

julia> JosephsonCircuits.sincosnloddtoboth([0.02+0.0im,0,0.01+0.0im,0],2,2)
4×2 Matrix{ComplexF64}:
       0.9996+0.0im       0.9999+0.0im
     0.019996-0.0im    0.0099995-0.0im
 -0.000199967+0.0im  -4.99979e-5+0.0im
   -2.6664e-6+0.0im  -3.33325e-7+0.0im
```
"""
function sincosnloddtoboth(amodd::Array{Complex{Float64},1},
    Nbranches::Int64,m::Int64)

    if length(amodd) != Nbranches*m
        error("Length of node flux vector not consistent with number of modes
        number of frequencies")
    end

    am = zeros(Complex{Float64},2*length(amodd))
    am[2:2:2*length(amodd)] .= amodd

    return sincosnl(reshape(am,2*m,Nbranches)) 
end


"""
    sincosnl(am::Array{Complex{Float64},2})

Applies the junction nonlinearity to a vector of Fourier coefficients of the
phases across the junction of size 2*m by (Nnodes-1) where m is the number of pump 
harmonics (0w, 1w, 2w, 3w, etc). To save time, this calculates both the sine and 
cosine nonlinearities at the same time. If the input is odd harmonics, the sine
terms will also be odd harmonics the cosine terms will be even harmonics.

# Examples
```
julia> JosephsonCircuits.sincosnl([0 0;0.001+0im 0;0 0;0 0; 0 0])
5×2 Matrix{ComplexF64}:
     0.999999+0.0im  1.0+0.0im
        0.001-0.0im  0.0-0.0im
      -5.0e-7+0.0im  0.0+0.0im
 -1.66667e-10+0.0im  0.0+0.0im
  8.33777e-14+0.0im  0.0+0.0im

julia> JosephsonCircuits.sincosnl([0 0;0.001+0im 0.25+0im;0 0;0 0; 0 0])
5×2 Matrix{ComplexF64}:
     0.999999+0.0im      0.93847+0.0im
        0.001-0.0im     0.242268-0.0im
      -5.0e-7+0.0im   -0.0306044+0.0im
 -1.66667e-10+0.0im  -0.00255568+0.0im
  8.33777e-14+0.0im  0.000321473+0.0im
```
"""
function sincosnl(am::Array{Complex{Float64},2})

    #choose the number of time points based on the number of fourier
    #coefficients
    #stepsperperiod = 2*size(am)[1]-2
    # changed to below because i wasn't using enough points when Nmodes=1.
    # the results contained only real values. 
    if size(am)[1] == 2
        stepsperperiod = 2*size(am)[1]-1
    else
        stepsperperiod = 2*size(am)[1]-2
    end        

    #transform back to time domain
    ift = FFTW.irfft(am,stepsperperiod,[1])*stepsperperiod

    #apply the nonlinear function
    nlift = cos.(ift) .+ sin.(ift)
    
    #fourier transform back to the frequency domain
    ftnlift = FFTW.rfft(nlift,[1])/stepsperperiod
    
    return ftnlift

end


function applynl(am::Array{Complex{Float64}},f::Function)

    #choose the number of time points based on the number of fourier
    #coefficients
    # changed to below because i wasn't using enough points when Nmodes=1.
    # the results contained only real values. 
    if size(am,1) == 2
        stepsperperiod = 2*size(am,1)-1
    else
        stepsperperiod = 2*size(am,1)-2
    end        

    #transform back to time domain
    ift = FFTW.irfft(am,stepsperperiod,1:length(size(am))-1)

    # normalize the fft
    normalization = prod(size(ift)[1:end-1])
    ift .*= normalization

    #apply the nonlinear function
    nlift = f.(ift)
    
    #fourier transform back to the frequency domain
    ftnlift = FFTW.rfft(nlift,1:length(size(am))-1)/normalization
    
    return ftnlift
    # should i make the fft plans and return them here?
    

end



"""
    calcindices(m::Integer)

The indices over which to calculate the idlers using the formula ws+2*i*wp 
where i is an index. This could be defined differently without causing any issues. 

# Examples
```jldoctest
julia> JosephsonCircuits.calcindices(7)
-3:3

julia> JosephsonCircuits.calcindices(8)
-4:3
```
"""
function calcindices(m::Integer)
    return -(m÷2):((m-1)÷2)
end

"""
    calcw(ws::Number,i::Integer,wp::Number)

Generate the signal and idler frequencies using the formula ws + 2*i*wp

Should I switch this to ws+i*wp so it can handle three wave mixing then 
always double i for four wave mixing?


# Examples
```jldoctest
julia> JosephsonCircuits.calcw(2*pi*4.0e9,-1,2*pi*5.0e9)/(2*pi*1.0e9)
-5.999999999999999

julia> JosephsonCircuits.calcw(2*pi*4.0e9,[-1,0,1],2*pi*5.0e9)/(2*pi*1.0e9)
3-element Vector{Float64}:
 -5.999999999999999
  4.0
 14.0

julia> JosephsonCircuits.calcw([2*pi*4.0e9,2*pi*4.1e9],[-1,0,1],2*pi*5.0e9)/(2*pi*1.0e9)
2×3 Matrix{Float64}:
 -6.0  4.0  14.0
 -5.9  4.1  14.1
```
"""
function calcw(ws,i::Integer,wp)
    return ws + 2*i*wp
end
function calcw(ws,i::AbstractVector,wp)

    w = zeros(typeof(ws),length(i))
    calcw!(ws,i,wp,w)
    return w
end
function calcw(ws::AbstractVector,i::AbstractVector,wp)

    w = zeros(eltype(ws),length(ws),length(i))
    calcw!(ws,i,wp,w)
    return w
end

"""
    calcw!(ws,i,wp,w)

Generate the signal and idler frequencies using the formula ws + 2*i*wp.
Overwrites w with output. 
"""
function calcw!(ws,i::AbstractVector,wp,w::AbstractVector)

    for j in 1:length(i)
        w[j] = calcw(ws,i[j],wp)
    end

    return nothing
end
function calcw!(ws::AbstractVector,i::AbstractVector,wp,w::AbstractMatrix)

    for j in 1:length(ws)
        for k in 1:length(i)
            w[j,k] = calcw(ws[j],i[k],wp)
        end
    end

    return nothing
end
