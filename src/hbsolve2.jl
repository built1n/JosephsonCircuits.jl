

"""
    hbsolve2()

New version of the harmonic balance solver suitable for arbitrary numbers of 
ports, sources, and pumps. Still under development. 
"""
function hbsolve2(ws, wp, Ip, Nsignalmodes, Npumpmodes, circuit, circuitdefs;
    pumpports = [1], solver = :klu, iterations = 1000, ftol = 1e-8,
    symfreqvar = nothing, nbatches = Base.Threads.nthreads(), sorting = :number,
    returnS = true, returnSnoise = false, returnQE = true, returnCM = true,
    returnnodeflux = false, returnvoltage = false, verbosity = 1)

    # solve the nonlinear system using the old syntax externally and the new
    # syntax internally
    w = (wp,)
    Nharmonics = (2*Npumpmodes,)
    sources = ((mode = (1,), port = pumpports[1], current = Ip),)

    # calculate the frequency struct
    freq = removeconjfreqs(
        truncfreqs(
            calcfreqsrdft(Nharmonics),
            dc=false, odd=true, even=false, maxintermodorder=Inf,
        )
    )

    indices = fourierindices(freq)

    Nmodes = length(freq.modes)

    # parse and sort the circuit
    psc = parsesortcircuit(circuit, sorting = sorting)

    # calculate the circuit graph
    cg = calccircuitgraph(psc)

    # calculate the numeric matrices
    nm=numericmatrices(psc, cg, circuitdefs, Nmodes = Nmodes)

    pump = hbnlsolve2(w, sources, freq, indices, psc, cg, nm;
        solver = solver, iterations = iterations, x0 = nothing, ftol = ftol,
        symfreqvar = symfreqvar)

    # the node flux
    nodeflux = pump.nodeflux

    # convert from node flux to branch flux
    phib = pump.Rbnm*nodeflux

    # calculate the sine and cosine nonlinearities from the pump flux
    Am = sincosnloddtoboth(phib[pump.Ljbm.nzind], length(pump.Ljb.nzind), pump.Nmodes)

    # solve the linear system
    signal=hblinsolve(ws, psc, cg, circuitdefs, wp = wp, Nmodes = Nsignalmodes,
        Am = Am, solver = solver, symfreqvar = symfreqvar, nbatches = nbatches,
        returnS = returnS, returnSnoise = returnSnoise, returnQE = returnQE,
        returnCM = returnCM, returnnodeflux = returnnodeflux,
        returnvoltage = returnvoltage, verbosity = verbosity)
    return HB(pump, Am, signal)
end

"""
    hbnlsolve2(w::NTuple{N,Any}, Nharmonics::NTuple{N,Int}, sources, circuit,
        circuitdefs; solver = :klu, iterations = 1000, maxintermodorder = Inf,
        dc = false, odd = true, even = false, x0 = nothing, ftol = 1e-8,
        symfreqvar = nothing, sorting= :number)

New version of the nonlinear harmonic balance solver suitable for arbitrary
numbers of ports, sources, and drives including direct current (zero frequency)
or flux pumping using a current source and a mutual inductor.

# Examples
```jldoctest compare=false
circuit = Array{Tuple{String,String,String,Union{Complex{Float64},Symbol,Int64}},1}(undef,0)
push!(circuit,("P1","1","0",1))
push!(circuit,("I1","1","0",:Ipump))
push!(circuit,("R1","1","0",:Rleft))
push!(circuit,("L1","1","0",:Lm)) 
push!(circuit,("K1","L1","L2",:K1))
push!(circuit,("C1","1","2",:Cc)) 
push!(circuit,("L2","2","3",:Lm)) 
push!(circuit,("Lj3","3","0",:Lj)) 
push!(circuit,("Lj4","2","0",:Lj)) 
push!(circuit,("C2","2","0",:Cj))
circuitdefs = Dict{Symbol,Complex{Float64}}(
    :Lj =>2000e-12,
    :Lm =>10e-12,
    :Cc => 200.0e-15,
    :Cj => 900e-15,
    :Rleft => 50.0,
    :Rright => 50.0,
    :Ipump => 1.0e-8,
    :K1 => 0.9,
)

Idc = 50e-5
Ip=0.0001e-6
wp=2*pi*5e9
Npumpmodes = 2
out=hbnlsolve2(
    (wp,),
    (Npumpmodes,),
    [
        (mode=(0,),port=1,current=Idc),
        (mode=(1,),port=1,current=Ip),
    ],
    circuit,circuitdefs;dc=true,odd=true,even=false)
isapprox(out.nodeflux,
    ComplexF64[15.190314040027522 - 8.56492651167657e-24im, 2.991103820177504e-6 - 1.8501001011477133e-8im, -6.835392148510984 - 1.0356102442254259e-14im, 7.396422335315908e-6 - 4.5749403967992827e-8im, 6.835392148539885 - 1.0356102451770844e-14im, 1.008026285172782e-5 - 6.23498762664213e-8im],
    atol = 1e-6)

# output
true
```
"""
function hbnlsolve2(
    w::NTuple{N,Any},
    Nharmonics::NTuple{N,Int},
    sources,
    circuit, circuitdefs; solver = :klu, iterations = 1000, maxintermodorder = Inf,
    dc = false, odd = true, even = false, x0 = nothing, ftol = 1e-8,
    symfreqvar = nothing, sorting= :number) where N

    # calculate the frequency struct
    freq = removeconjfreqs(
        truncfreqs(
            calcfreqsrdft(Nharmonics),
            dc=dc, odd=odd, even=even, maxintermodorder=maxintermodorder,
        )
    )

    indices = fourierindices(freq)

    Nmodes = length(freq.modes)

    # parse and sort the circuit
    psc = parsesortcircuit(circuit, sorting = sorting)

    # calculate the circuit graph
    cg = calccircuitgraph(psc)

    # calculate the numeric matrices
    nm=numericmatrices(psc, cg, circuitdefs, Nmodes = Nmodes)

    return hbnlsolve2(w, sources, freq, indices, psc, cg, nm;
        solver = solver, iterations = iterations, x0 = x0, ftol = ftol,
        symfreqvar = symfreqvar)
end

function hbnlsolve2(
    w::NTuple{N,Any},
    sources,
    frequencies::Frequencies{N},
    indices::FourierIndices{N}, psc::ParsedSortedCircuit, cg::CircuitGraph,
    nm::CircuitMatrices; solver = :klu, iterations = 1000, x0 = nothing,
    ftol = 1e-8, symfreqvar = nothing) where N

    Nharmonics = frequencies.Nharmonics
    Nw = frequencies.Nw
    Nt = frequencies.Nt
    coords = frequencies.coords
    modes = frequencies.modes

    conjsymdict = indices.conjsymdict
    freqindexmap = indices.vectomatmap
    conjsourceindices = indices.conjsourceindices
    conjtargetindices = indices.conjtargetindices
    Amatrixmodes = indices.hbmatmodes
    Amatrixindices = indices.hbmatindices

    # generate the frequencies of the modes
    Nmodes = length(modes)
    wmodes = calcmodefreqs(w,modes)

    # extract the elements we need
    Nnodes = psc.Nnodes
    nodeindexarraysorted = psc.nodeindexarraysorted
    Nbranches = cg.Nbranches
    edge2indexdict = cg.edge2indexdict
    Ljb = nm.Ljb
    Ljbm = nm.Ljbm
    Rbnm = nm.Rbnm
    Cnm = nm.Cnm
    Gnm = nm.Gnm
    invLnm = nm.invLnm
    portindices = nm.portindices
    portnumbers = nm.portnumbers
    portimpedanceindices = nm.portimpedanceindices
    Lmean = nm.Lmean
    Lb = nm.Lb

    # calculate the diagonal frequency matrices
    wmodesm = Diagonal(repeat(wmodes, outer = Nnodes-1))
    wmodes2m = Diagonal(repeat(wmodes.^2, outer = Nnodes-1))

    # calculate the source terms in the branch basis
    bbm = calcsources(modes, sources, portindices, portnumbers,
        nodeindexarraysorted, edge2indexdict, Lmean, Nnodes, Nbranches, Nmodes)

    # convert from the node basis to the branch basis
    bnm = transpose(Rbnm)*bbm

    # calculate the dimensions of the array which holds the frequency
    # domain information for the fourier transform
    Nwtuple = NTuple{length(Nw)+1,Int}((Nw...,length(Ljb.nzval)))

    # create an array to hold the frequency domain data for the
    # fourier transform
    phimatrix = zeros(Complex{Float64}, Nwtuple)

    # create an array to hold the time domain data for the RFFT. also generate
    # the plans.
    phimatrixtd, irfftplan, rfftplan = plan_applynl(phimatrix)

    # initializing this with zeros seems to cause problems
    # ideally i should initialize the vector of ones then convert to the
    # matrix.
    Amatrix = ones(Complex{Float64}, Nwtuple)
    Nfreq = prod(size(Amatrix)[1:end-1])
    AoLjbmindices, conjindicessorted = calcAoLjbmindices(Amatrixindices,
        Ljb, Nmodes, Nbranches, Nfreq)

    # right now i redo the calculation of AoLjbmindices, conjindicessorted in calcAoLjbm2
    AoLjbm = calcAoLjbm2(Amatrix, Amatrixindices, Ljb, Lmean, Nmodes, Nbranches)
    AoLjbmcopy = calcAoLjbm2(Amatrix, Amatrixindices, Ljb, Lmean, Nmodes, Nbranches)

    # convert to a sparse node matrix. Note: I was having problems with type 
    # instability when i used AoLjbm here instead of AoLjbmcopy. 
    AoLjnm = transpose(Rbnm)*AoLjbmcopy*Rbnm;

    if x0 == nothing
        x = zeros(Complex{Float64}, (Nnodes-1)*Nmodes)
    else
        x = x0
    end
    F = zeros(Complex{Float64}, (Nnodes-1)*Nmodes)
    AoLjbmvector = zeros(Complex{Float64}, Nbranches*Nmodes)

    # make a sparse transpose (improves multiplication speed slightly)
    Rbnmt = sparse(transpose(Rbnm))

    # substitute in the mode frequencies for components which have frequency
    # defined symbolically.
    Cnm = freqsubst(Cnm, wmodes, symfreqvar)
    Gnm = freqsubst(Gnm, wmodes, symfreqvar)
    invLnm = freqsubst(invLnm, wmodes, symfreqvar)

    # scale the matrices for numerical reasons
    Cnm *= Lmean
    Gnm *= Lmean
    invLnm *= Lmean

    # Calculate an initial Jacobian in order to create the factorization object.
    # This need to have the same sparsity structure as the actual Jacobian. If
    # the numerical values are vastly different from the actual Jacobian this
    # can cause a singular value error in klu! when we attempt to reuse the
    # symbolic factorization. We perform the sparse matrix addition keeping
    # numerical zeros (the usual sparse matrix addition converts these to
    # structural zeros which would change the sparsity structure).
    # J .= AoLjnm + invLnm + im*Gnm*wmodesm - Cnm*wmodes2m
    J = spaddkeepzeros(spaddkeepzeros(spaddkeepzeros(AoLjnm, invLnm), im*Gnm*wmodesm), - Cnm*wmodes2m)

    # make the arrays and datastructures we need for
    # the non-allocating sparse matrix multiplication.
    AoLjbmRbnm = AoLjbmcopy*Rbnm
    xbAoLjbmRbnm = fill(false, size(AoLjbmcopy, 1))
    AoLjnm = Rbnmt*AoLjbmRbnm
    xbAoLjnm = fill(false, size(Rbnmt, 1))

    # make the index maps so we can add the sparse matrices together without
    # memory allocations. 
    AoLjnmindexmap = sparseaddmap(J, AoLjnm)
    invLnmindexmap = sparseaddmap(J, invLnm)
    Gnmindexmap = sparseaddmap(J, Gnm)
    Cnmindexmap = sparseaddmap(J, Cnm)

    # build the function and Jacobian for solving the nonlinear system
    function fj!(F, J, x)
        calcfj2!(F, J, x, wmodesm, wmodes2m, Rbnm, Rbnmt, invLnm,
            Cnm, Gnm, bnm, Ljb, Ljbm, Nmodes,
            Nbranches, Lmean, AoLjbmvector, AoLjbm,
            AoLjnmindexmap, invLnmindexmap, Gnmindexmap, Cnmindexmap,
            AoLjbmindices, conjindicessorted,
            freqindexmap, conjsourceindices, conjtargetindices, phimatrix,
            AoLjnm, xbAoLjnm, AoLjbmRbnm, xbAoLjbmRbnm,
            phimatrixtd, irfftplan, rfftplan,
        )
        return nothing
    end

    # solve the nonlinear system
    nlsolve!(fj!, F, J, x; iterations = iterations, ftol = ftol)

    nodeflux = x

    # calculate the scattering parameters for the pump
    Nports = length(portindices)
    # input = Diagonal(zeros(Complex{Float64}, Nports*Nmodes))
    # output = zeros(Complex{Float64}, Nports*Nmodes)
    # phibports = zeros(Complex{Float64}, Nports*Nmodes)
    # inputval = zero(Complex{Float64})
    S = zeros(Complex{Float64}, Nports*Nmodes, Nports*Nmodes)

    return NonlinearHB(nodeflux, Rbnm, Ljb, Lb, Ljbm, Nmodes, Nbranches, S)

end


"""
    calcfj2(F,J,phin,wmodesm,wmodes2m,Rbnm,invLnm,Cnm,Gnm,bm,Ljb,Ljbindices,
        Ljbindicesm,Nmodes,Lmean,AoLjbm)
        
Calculate the residual and the Jacobian. These are calculated with one function
in order to reuse as much as possible.

Leave off the type signatures on F and J because the solver will pass a type of
Nothing if it only wants to calculate F or J. 

"""
function calcfj2!(F,
        J,
        nodeflux::AbstractVector,
        wmodesm::AbstractMatrix,
        wmodes2m::AbstractMatrix,
        Rbnm::AbstractArray{Int, 2},
        Rbnmt::AbstractArray{Int, 2},
        invLnm::AbstractMatrix,
        Cnm::AbstractMatrix,
        Gnm::AbstractMatrix,
        bnm::AbstractVector,
        Ljb::SparseVector,
        Ljbm::SparseVector,
        Nmodes::Int,
        Nbranches::Int,
        Lmean,
        AoLjbmvector::AbstractVector,
        AoLjbm, AoLjnmindexmap, invLnmindexmap, Gnmindexmap, Cnmindexmap,
        AoLjbmindices, conjindicessorted,
        freqindexmap, conjsourceindices, conjtargetindices, phimatrix,
        AoLjnm, xbAoLjnm, AoLjbmRbnm, xbAoLjbmRbnm,
        phimatrixtd, irfftplan, rfftplan,
        )

    # convert from a node flux to a branch flux
    phib = Rbnm*nodeflux

    if !(F == nothing)

        # convert the branch flux vector to a matrix with the terms arranged
        # in the correct way for the inverse rfft including the appropriate
        # complex conjugates.
        phivectortomatrix!(phib[Ljbm.nzind], phimatrix, freqindexmap,
            conjsourceindices, conjtargetindices, length(Ljb.nzval))

        # apply the sinusoidal nonlinearity when evaluaing the function
        applynl!(phimatrix, phimatrixtd, (x) -> sin(x), irfftplan, rfftplan)

        # convert the sinphimatrix to a vector
        fill!(AoLjbmvector, 0)
        AoLjbmvectorview = view(AoLjbmvector, Ljbm.nzind)
        phimatrixtovector!(AoLjbmvectorview, phimatrix, freqindexmap,
            conjsourceindices, conjtargetindices, length(Ljb.nzval))

        for i in eachindex(AoLjbmvectorview)
            AoLjbmvectorview[i] = AoLjbmvectorview[i] * (Lmean/Ljbm.nzval[i])
        end

        F .= Rbnmt*AoLjbmvector .+ invLnm*nodeflux .+ im*Gnm*wmodesm*nodeflux .- Cnm*wmodes2m*nodeflux .- bnm

    end

    #calculate the Jacobian
    if !(J == nothing)

        # turn the phivector into a matrix again because applynl! overwrites
        # the frequency domain data
        phivectortomatrix!(phib[Ljbm.nzind], phimatrix, freqindexmap,
            conjsourceindices, conjtargetindices, length(Ljb.nzval))

        # apply a cosinusoidal nonlinearity when evaluating the Jacobian
        applynl!(phimatrix, phimatrixtd, (x) -> cos(x), irfftplan, rfftplan)

        # calculate  AoLjbm
        updateAoLjbm2!(AoLjbm, phimatrix, AoLjbmindices, conjindicessorted,
            Ljb, Lmean)

        # convert to a sparse node matrix
        # AoLjnm = Rbnmt*AoLjbm*Rbnm
        # non allocating sparse matrix multiplication
        spmatmul!(AoLjbmRbnm, AoLjbm, Rbnm, xbAoLjbmRbnm)
        spmatmul!(AoLjnm, Rbnmt, AoLjbmRbnm, xbAoLjnm)

        # calculate the Jacobian. If J is sparse, keep it sparse. 
        # J .= AoLjnm + invLnm + im*Gnm*wmodesm - Cnm*wmodes2m
        # the code below adds the sparse matrices together with minimal
        # memory allocations and without changing the sparsity structure.
        fill!(J, 0)
        sparseadd!(J, AoLjnm, AoLjnmindexmap)
        sparseadd!(J, invLnm, invLnmindexmap)
        sparseadd!(J, im, Gnm, wmodesm, Gnmindexmap)
        sparseadd!(J, -1, Cnm, wmodes2m, Cnmindexmap)
    end
    return nothing
end

"""
    calcAoLjbmindices(Amatrixindices,Ljb::SparseVector,Nmodes,Nbranches,Nfreq)

Return the sparse matrix containing the indices from the frequency domain
RFFT data as well as the indices of the sparse matrix to conjugate.

# Examples
```jldoctest
Amatrixindices = [1 -2 -3 -4; 2 1 -2 -3; 3 2 1 -2; 4 3 2 1]
Ljb = JosephsonCircuits.SparseArrays.sparsevec([1,2],[1.0,1.0])
Nmodes = 4
Nbranches = length(Ljb)
Nfreq = 4
AoLjbmindices, conjindicessorted, nentries = JosephsonCircuits.calcAoLjbmindices(
    Amatrixindices,
    Ljb,
    Nmodes,
    Nbranches,
    Nfreq);
AoLjbmindices

# output
8×8 SparseArrays.SparseMatrixCSC{Int64, Int64} with 32 stored entries:
 1  2  3  4  ⋅  ⋅  ⋅  ⋅
 2  1  2  3  ⋅  ⋅  ⋅  ⋅
 3  2  1  2  ⋅  ⋅  ⋅  ⋅
 4  3  2  1  ⋅  ⋅  ⋅  ⋅
 ⋅  ⋅  ⋅  ⋅  5  6  7  8
 ⋅  ⋅  ⋅  ⋅  6  5  6  7
 ⋅  ⋅  ⋅  ⋅  7  6  5  6
 ⋅  ⋅  ⋅  ⋅  8  7  6  5
```
```jldoctest
Amatrixindices = [1 -2 -3 -4; 2 1 -2 -3; 3 2 1 -2; 4 3 2 1]
Ljb = JosephsonCircuits.SparseArrays.sparsevec([1,3],[1.0,1.0])
Nmodes = 4
Nbranches = length(Ljb)
Nfreq = 4
AoLjbmindices, conjindicessorted, nentries = JosephsonCircuits.calcAoLjbmindices(
    Amatrixindices,
    Ljb,
    Nmodes,
    Nbranches,
    Nfreq);
for c in conjindicessorted;AoLjbmindices.nzval[c] = -AoLjbmindices.nzval[c];end;AoLjbmindices

# output
12×12 SparseArrays.SparseMatrixCSC{Int64, Int64} with 32 stored entries:
 1  -2  -3  -4  ⋅  ⋅  ⋅  ⋅  ⋅   ⋅   ⋅   ⋅
 2   1  -2  -3  ⋅  ⋅  ⋅  ⋅  ⋅   ⋅   ⋅   ⋅
 3   2   1  -2  ⋅  ⋅  ⋅  ⋅  ⋅   ⋅   ⋅   ⋅
 4   3   2   1  ⋅  ⋅  ⋅  ⋅  ⋅   ⋅   ⋅   ⋅
 ⋅   ⋅   ⋅   ⋅  ⋅  ⋅  ⋅  ⋅  ⋅   ⋅   ⋅   ⋅
 ⋅   ⋅   ⋅   ⋅  ⋅  ⋅  ⋅  ⋅  ⋅   ⋅   ⋅   ⋅
 ⋅   ⋅   ⋅   ⋅  ⋅  ⋅  ⋅  ⋅  ⋅   ⋅   ⋅   ⋅
 ⋅   ⋅   ⋅   ⋅  ⋅  ⋅  ⋅  ⋅  ⋅   ⋅   ⋅   ⋅
 ⋅   ⋅   ⋅   ⋅  ⋅  ⋅  ⋅  ⋅  5  -6  -7  -8
 ⋅   ⋅   ⋅   ⋅  ⋅  ⋅  ⋅  ⋅  6   5  -6  -7
 ⋅   ⋅   ⋅   ⋅  ⋅  ⋅  ⋅  ⋅  7   6   5  -6
 ⋅   ⋅   ⋅   ⋅  ⋅  ⋅  ⋅  ⋅  8   7   6   5
```
"""
function calcAoLjbmindices(Amatrixindices::Matrix, Ljb::SparseVector, Nmodes,
    Nbranches, Nfreq)

    # evaluate Amatrixindices to find the number of entries of each type
    nentries = 0
    nconjentries = 0
    nzeros = 0
    for j in 1:Nmodes
        for k in 1:Nmodes
            if Amatrixindices[j,k] == 0
                nzeros += 1
            else
                nentries += 1
                if Amatrixindices[j,k] < 0
                    nconjentries += 1
                end
            end
        end
    end

    # make these into a sparse matrix. skip any zeros
    conjindices = Vector{Int}(undef, nconjentries * nnz(Ljb))
    I = Vector{Int}(undef, nentries * nnz(Ljb))
    J = Vector{Int}(undef, nentries * nnz(Ljb))
    V = Vector{Int}(undef, nentries * nnz(Ljb))
    Vsort = Vector{Int}(undef, nentries * nnz(Ljb))

    # generate the contents of the sparse matrix 
    n = 1
    nconj = 1
    for i in 1:nnz(Ljb)
        for j in 1:Nmodes
            for k in 1:Nmodes
                if Amatrixindices[j,k] != 0
                    I[n] = j + (Ljb.nzind[i] - 1) * Nmodes
                    J[n] = k + (Ljb.nzind[i] - 1) * Nmodes
                    Vsort[n] = n
                    index = abs(Amatrixindices[j,k]) + Nfreq * (i - 1)
                    V[n] = index
                    if Amatrixindices[j,k] < 0
                        conjindices[nconj] = n
                        nconj += 1
                    end
                    n += 1
                end
            end
        end
    end

    # create the sparse matrix
    AoLjbmindices = sparse(I, J, Vsort, Nbranches * Nmodes, Nbranches * Nmodes)

    # find the sorting of nzvals in the sparse matrix and apply that same
    # sorting to 
    Vsort2 = copy(AoLjbmindices.nzval)
    conjindicessorted = Vsort2[conjindices]

    AoLjbmindices.nzval .= V[Vsort2]

    return AoLjbmindices, conjindicessorted, nentries

end


"""
    calcAoLjbm2(Am::Array, Amatrixindices::Matrix, Ljb::SparseVector, Lmean,
        Nmodes, Nbranches, Nfreq)

Return the harmonic balance matrix divided by the Josephson inductance.

# Examples
```jldoctest
Amatrix = ComplexF64[1.0 + 1.0im 1.0 + 1.0im; 1.0 + 1.0im 1.0 + 1.0im; 1.0 + 1.0im 1.0 + 1.0im]
Amatrixindices = [1 -2 -3; 2 1 -2; 3 2 1]
Ljb = JosephsonCircuits.SparseArrays.sparsevec([1,2],[1.0,2.0])
Lmean = 1
Nmodes = 3
Nbranches = 2
JosephsonCircuits.calcAoLjbm2(Amatrix, Amatrixindices, Ljb, Lmean, Nmodes, Nbranches)

# output
6×6 SparseArrays.SparseMatrixCSC{ComplexF64, Int64} with 18 stored entries:
 1.0+1.0im  1.0-1.0im  1.0-1.0im      ⋅          ⋅          ⋅    
 1.0+1.0im  1.0+1.0im  1.0-1.0im      ⋅          ⋅          ⋅    
 1.0+1.0im  1.0+1.0im  1.0+1.0im      ⋅          ⋅          ⋅    
     ⋅          ⋅          ⋅      0.5+0.5im  0.5-0.5im  0.5-0.5im
     ⋅          ⋅          ⋅      0.5+0.5im  0.5+0.5im  0.5-0.5im
     ⋅          ⋅          ⋅      0.5+0.5im  0.5+0.5im  0.5+0.5im
```
```jldoctest
@variables A11 A12 A21 A22 A31 A32 Lj1 Lj2
Amatrix = [A11 A12;A21 A22;A31 A32]
Amatrixindices = [1 -2 -3; 2 1 -2; 3 2 1]
Ljb = JosephsonCircuits.SparseArrays.sparsevec([1,2],[Lj1,Lj2])
Lmean = 1
Nmodes = 3
Nbranches = 2
JosephsonCircuits.calcAoLjbm2(Amatrix, Amatrixindices, Ljb, Lmean, Nmodes, Nbranches)

# output
6×6 SparseArrays.SparseMatrixCSC{Num, Int64} with 18 stored entries:
 A11 / Lj1  A21 / Lj1  A31 / Lj1          ⋅          ⋅          ⋅
 A21 / Lj1  A11 / Lj1  A21 / Lj1          ⋅          ⋅          ⋅
 A31 / Lj1  A21 / Lj1  A11 / Lj1          ⋅          ⋅          ⋅
         ⋅          ⋅          ⋅  A12 / Lj2  A22 / Lj2  A32 / Lj2
         ⋅          ⋅          ⋅  A22 / Lj2  A12 / Lj2  A22 / Lj2
         ⋅          ⋅          ⋅  A32 / Lj2  A22 / Lj2  A12 / Lj2
```
"""
function calcAoLjbm2(Am::Array, Amatrixindices::Matrix, Ljb::SparseVector,
    Lmean, Nmodes, Nbranches)

    Nfreq = prod(size(Am)[1:end-1])


    # calculate the sparse matrix filled with the indices of Am
    AoLjbmindices, conjindicessorted, Nfreq = calcAoLjbmindices(Amatrixindices,
        Ljb, Nmodes, Nbranches, Nfreq)

    # determine the type to use for AoLjbm
    type = promote_type(eltype(Am), eltype(1 ./Ljb.nzval))

    if type <: Symbolic
        type = Any
    end

    nzval = Vector{type}(undef, nnz(AoLjbmindices))

    AoLjbm = SparseMatrixCSC(AoLjbmindices.m, AoLjbmindices.n,
        AoLjbmindices.colptr, AoLjbmindices.rowval, nzval)

    updateAoLjbm2!(AoLjbm, Am, AoLjbmindices, conjindicessorted, Ljb, Lmean)

    return AoLjbm

end



"""

Update the values in the sparse AoLjbm matrix in place.

"""
function updateAoLjbm2!(AoLjbm::SparseMatrixCSC,Am::Array, AoLjbmindices,
    conjindicessorted, Ljb::SparseVector, Lmean)

    nentries = nnz(AoLjbm) ÷ nnz(Ljb)

    # does this run into problems if the inductance vector isn't sorted?
    # can i guarantee that Ljb is always sorted? look into this
    # copy over the values and scale by the inductance
    for i in eachindex(AoLjbm.nzval)
        # j = indexconvert[i ÷ (Nfreq+1)+1]
        j = i ÷ (nentries+1) + 1
        AoLjbm.nzval[i] = Am[AoLjbmindices.nzval[i]] * (Lmean / Ljb.nzval[j])
    end


    # # i think this will work even if they aren't sorted
    # # copy over the values and scale by the inductance
    # indexconvert = zeros(Int,length(Ljb))
    # for (i,j) in enumerate(Ljb.nzind)
    #     indexconvert[j] = i
    # end

    # for i = 1:length(AoLjbm.colptr)-1
    #     for j in AoLjbm.colptr[i]:(AoLjbm.colptr[i+1]-1)
    #         k = j ÷ (nentries+1)+1
    #         AoLjbm.nzval[j] = Am[AoLjbmindices.nzval[j]]*(Lmean/Ljb.nzval[k])
    #     end
    # end

    # take the complex conjugates
    for i in conjindicessorted
        AoLjbm.nzval[i] = conj(AoLjbm.nzval[i])
    end

    return nothing
end

"""
    calcsources(modes, sources, portindices, portnumbers, nodeindexarraysorted,
        edge2indexdict, Lmean, Nnodes, Nbranches, Nmodes)

Calculate the source terms in the branch basis. See also [`calcsources`](@ref).

# Examples
```jldoctest
modes = [(0,), (1,)]
sources = NamedTuple{(:mode, :port, :current), Tuple{Tuple{Int64}, Int64, Float64}}[(mode = (0,), port = 1, current = 0.0005), (mode = (1,), port = 1, current = 1.0e-10)]
portindices = [1]
portnumbers = [1]
nodeindexarraysorted = [2 2 2 2 0 2 3 4 3 3; 1 1 1 1 0 3 4 1 1 1]
edge2indexdict = Dict((1, 2) => 1, (3, 1) => 2, (1, 3) => 2, (4, 1) => 3, (2, 1) => 1, (1, 4) => 3, (3, 4) => 4, (4, 3) => 4)
Lmean = 1.005e-9 + 0.0im
Nnodes = 4
Nbranches = 4
Nmodes = 2
JosephsonCircuits.calcsources(modes, sources, portindices, portnumbers,
    nodeindexarraysorted, edge2indexdict, Lmean, Nnodes, Nbranches, Nmodes)

# output
8-element Vector{ComplexF64}:
     1526.863796602709 + 0.0im
 0.0003053727593205418 + 0.0im
                   0.0 + 0.0im
                   0.0 + 0.0im
                   0.0 + 0.0im
                   0.0 + 0.0im
                   0.0 + 0.0im
                   0.0 + 0.0im
```
"""
function calcsources(modes, sources, portindices, portnumbers, nodeindexarraysorted,
    edge2indexdict, Lmean, Nnodes, Nbranches, Nmodes)

    bbm = zeros(Complex{Float64}, Nbranches*Nmodes)

    calcsources!(bbm, modes, sources, portindices, portnumbers,
        nodeindexarraysorted, edge2indexdict, Lmean, Nnodes, Nbranches,
        Nmodes)

    return bbm
end

"""
    calcsources!(bbm, modes, sources, portindices, portnumbers,
        nodeindexarraysorted, edge2indexdict, Lmean, Nnodes, Nbranches, Nmodes)

Calculate the source terms in the branch basis. Overwrite bbm with the output.
See also [`calcsources`](@ref).
"""
function calcsources!(bbm, modes, sources, portindices, portnumbers,
    nodeindexarraysorted, edge2indexdict, Lmean, Nnodes, Nbranches, Nmodes)

    for source in sources
        # for (key,val) in portdict
        for i in eachindex(portindices)
            portnumber = portnumbers[i]
            portindex = portindices[i]
            key = (nodeindexarraysorted[1, portindex], nodeindexarraysorted[2, portindex])

            if portnumber == source[:port]
                # now i have to find the index.
                # this will depend on the frequency index
                # i should calculate that in the right way now.
                for j in eachindex(modes)
                    if modes[j] == source[:mode]
                        bbm[(edge2indexdict[key]-1)*Nmodes+j] = Lmean*source[:current]/phi0
                        break
                    end
                end
                break
            end
        end
    end

    return nothing
end