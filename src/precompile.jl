
# these precompile directives are to help the compiler perform type inference
# during the precompilation stage (when the package is installed) instead of
# when it is loaded or the functions are run. this is a helpful guide:
# https://timholy.github.io/SnoopCompile.jl/stable/snoopi_deep_analysis/#inferrability
# and the basic commands to look at the inference triggers
# julia> using SnoopCompile
# julia> using QCE
# julia> tinf = @snoopi_deep QCE.warmup();
# julia> itrigs = inference_triggers(tinf)


precompile(iterate,(Vector{Pair{Tuple{Int64, Int64}, Number}},))
precompile(Base.indexed_iterate,(Pair{Tuple{Int64, Int64}, Number}, Int64))
precompile(setindex!,(Dict{Tuple{Int64, Int64},Number},Int64,Tuple{Int64, Int64}))
precompile(setindex!,(Dict{Tuple{Int64, Int64}, Number}, ComplexF64, Tuple{Int64, Int64}))
precompile(setindex!,(Dict{Tuple{Int64, Int64}, Real}, Int64, Tuple{Int64, Int64}))
precompile(setindex!,(Dict{Tuple{Int64, Int64}, Real}, Float64, Tuple{Int64, Int64}))
precompile(setindex!,(LinearAlgebra.Diagonal{ComplexF64, Vector{ComplexF64}}, ComplexF64, Int64, Int64))
precompile(setindex!,(LinearAlgebra.Diagonal{ComplexF64, Vector{ComplexF64}}, Float64, Int64, Int64))
precompile(setindex!,(Base.RefValue{Symbol}, Symbol))
precompile(collect,(Dict{Tuple{Int64, Int64}, Number},))
precompile(copyto!,(Vector{ComplexF64}, SubArray{ComplexF64, 2, Matrix{ComplexF64}, Tuple{UnitRange{Int64}, Base.Slice{Base.OneTo{Int64}}}, false}))
precompile(copyto!,(Matrix{ComplexF64}, SubArray{ComplexF64, 2, Matrix{ComplexF64}, Tuple{UnitRange{Int64}, Base.Slice{Base.OneTo{Int64}}}, false}))
precompile(view,(Matrix{ComplexF64}, UnitRange{Int64}, Function))
precompile(sortperm,(Vector{Real},))
precompile(collect,(Base.ValueIterator{Dict{Tuple{Int64, Int64}, Real}},))
precompile(values,(Dict{Tuple{Int64, Int64}, Real},))

precompile(-,(ComplexF64, Int64))
precompile(/,(Vector{ComplexF64}, Float64))
precompile(*,(Complex{Bool}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, LinearAlgebra.Diagonal{Float64, Vector{Float64}}))
precompile(*,(Complex{Bool}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}))
precompile(*,(SparseArrays.SparseMatrixCSC{Int64, Int64}, ComplexF64))
precompile(*,(SparseArrays.SparseMatrixCSC{Float64, Int64}, ComplexF64))
precompile(*,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, ComplexF64))
precompile(*,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Float64))
precompile(+,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}))
precompile( +,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}))
precompile(-,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}))

precompile(FFTW.maybe_destroy_plan,(FFTW.rFFTWPlan{Float64, -1, false, 2, Vector{Int64}},))
precompile(FFTW.maybe_destroy_plan,(FFTW.rFFTWPlan{ComplexF64, 1, false, 2, Vector{Int64}},))

precompile(KLU.increment!,(Vector{Int64},))
precompile(KLU.solve!,(KLU.KLUFactorization{ComplexF64, Int64}, Matrix{ComplexF64}))
precompile(KLU.klu,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64},))
precompile(KLU.klu!,(KLU.KLUFactorization{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}))
precompile(KLU.klu!,(KLU.KLUFactorization{ComplexF64, Int64}, Vector{ComplexF64}))
precompile(KLU.LibKLU.klu_zl_solve,(Ptr{Nothing}, Ptr{Nothing}, Int64, Int64, Matrix{ComplexF64}, Base.RefValue{KLU.LibKLU.klu_l_common_struct}))
precompile(KLU.LibKLU.klu_zl_refactor,(Vector{Int64}, Vector{Int64}, Vector{ComplexF64}, Ptr{Nothing}, Ptr{Nothing}, Base.RefValue{KLU.LibKLU.klu_l_common_struct}))
precompile(KLU.LibKLU.klu_zl_factor,(Vector{Int64}, Vector{Int64}, Vector{ComplexF64}, Ptr{Nothing}, Base.RefValue{KLU.LibKLU.klu_l_common_struct}))
precompile(KLU.LibKLU.klu_l_analyze,(Int64, Vector{Int64}, Vector{Int64}, Base.RefValue{KLU.LibKLU.klu_l_common_struct}))
precompile(KLU.LibKLU.klu_zl_solve,(Ptr{Nothing}, Ptr{Nothing}, Int64, Int64, Vector{ComplexF64}, Base.RefValue{KLU.LibKLU.klu_l_common_struct}))

precompile(LinearAlgebra.ldiv!,(Matrix{ComplexF64}, KLU.KLUFactorization{ComplexF64, Int64}, Matrix{ComplexF64}))

precompile(SparseArrays.sparsevec,(Vector{Int64}, Vector{Int64}, Int64))
precompile(SparseArrays.sparsevec,(Vector{Int64}, Vector{ComplexF64}, Int64))

# functions from this module
precompile(JosephsonCircuits.calcAoLjbm,(Matrix{ComplexF64}, SparseArrays.SparseVector{ComplexF64, Int64}, Vector{Int64}, ComplexF64, Int64, Int64, Vector{Int64}, Vector{Int64}, Vector{ComplexF64}))
precompile(JosephsonCircuits.calcAoLjbm,(Matrix{ComplexF64}, SparseArrays.SparseVector{ComplexF64, Int64}, Vector{Int64}, Float64, Int64, Int64, Vector{Int64}, Vector{Int64}, Vector{ComplexF64}))
precompile(JosephsonCircuits.calcAoLjbm,(Matrix{ComplexF64}, SparseArrays.SparseVector{Float64, Int64}, Vector{Int64}, Float64, Int64, Int64, Vector{Int64}, Vector{Int64}, Vector{ComplexF64}))

precompile(JosephsonCircuits.calcbranchvector,(Vector{Symbol}, Matrix{Int64}, Vector{Number}, Vector{Float64}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64, Symbol))
precompile(JosephsonCircuits.calcbranchvector,(Vector{Symbol}, Matrix{Int64}, Vector{Number}, Vector{ComplexF64}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64, Symbol))
precompile(JosephsonCircuits.calcbranchvector,(Vector{Symbol}, Matrix{Int64}, Vector{Real}, Vector{Float64}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64, Symbol))
precompile(JosephsonCircuits.calcbranchvector,(Vector{Symbol}, Matrix{Int64}, Vector{Real}, Vector{Nothing}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64, Symbol))
precompile(JosephsonCircuits.calcbranchvector,(Vector{Symbol}, Matrix{Int64}, Vector{Number}, Vector{Nothing}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64, Symbol))

precompile(JosephsonCircuits.calcCn,(Vector{Symbol}, Matrix{Int64}, Vector{Real}, Int64, Int64))
precompile(JosephsonCircuits.calcGn,(Vector{Symbol}, Matrix{Int64}, Vector{Real}, Int64, Int64))

precompile(JosephsonCircuits.calcfj!,(Nothing, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{ComplexF64}, LinearAlgebra.Diagonal{Float64, Vector{Float64}}, LinearAlgebra.Diagonal{Float64, Vector{Float64}}, SparseArrays.SparseMatrixCSC{Int64, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{ComplexF64}, SparseArrays.SparseVector{ComplexF64, Int64}, Vector{Int64}, Vector{Int64}, Int64, Int64, ComplexF64, Vector{ComplexF64}, Vector{Int64}, Vector{Int64}, Vector{ComplexF64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{UInt32}, Vector{UInt32}, Vector{UInt32}, Vector{UInt32}))
precompile(JosephsonCircuits.calcfj!,(Vector{ComplexF64}, Nothing, Vector{ComplexF64}, LinearAlgebra.Diagonal{Float64, Vector{Float64}}, LinearAlgebra.Diagonal{Float64, Vector{Float64}}, SparseArrays.SparseMatrixCSC{Int64, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{ComplexF64}, SparseArrays.SparseVector{ComplexF64, Int64}, Vector{Int64}, Vector{Int64}, Int64, Int64, ComplexF64, Vector{ComplexF64}, Vector{Int64}, Vector{Int64}, Vector{ComplexF64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{UInt32}, Vector{UInt32}, Vector{UInt32}, Vector{UInt32}))
precompile(JosephsonCircuits.calcfj!,(Vector{ComplexF64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{ComplexF64}, LinearAlgebra.Diagonal{Float64, Vector{Float64}}, LinearAlgebra.Diagonal{Float64, Vector{Float64}}, SparseArrays.SparseMatrixCSC{Int64, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{ComplexF64}, SparseArrays.SparseVector{ComplexF64, Int64}, Vector{Int64}, Vector{Int64}, Int64, Int64, ComplexF64, Vector{ComplexF64}, Vector{Int64}, Vector{Int64}, Vector{ComplexF64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{UInt32}, Vector{UInt32}, Vector{UInt32}, Vector{UInt32}))

precompile(JosephsonCircuits.calcinvLn,(SparseArrays.SparseVector{Int64, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}, Int64))
precompile(JosephsonCircuits.calcinvLn,(SparseArrays.SparseVector{Float64, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}, Int64))
precompile(JosephsonCircuits.calcinvLn,(SparseArrays.SparseVector{Nothing, Int64}, SparseArrays.SparseMatrixCSC{Nothing, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}, Int64))

precompile(JosephsonCircuits.calcinput!,(LinearAlgebra.Diagonal{ComplexF64, Vector{ComplexF64}}, Float64, Matrix{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Dict{Tuple{Int64, Int64}, Number}, Vector{Float64}))
precompile(JosephsonCircuits.calcinput!,(LinearAlgebra.Diagonal{ComplexF64, Vector{ComplexF64}}, Float64, Vector{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Dict{Tuple{Int64, Int64}, Number}, Vector{Float64}))
precompile(JosephsonCircuits.calcinput!,(LinearAlgebra.Diagonal{ComplexF64, Vector{ComplexF64}}, Float64, Matrix{ComplexF64}, Dict{Tuple{Int64, Int64}, Real}, Dict{Tuple{Int64, Int64}, Real}, Vector{Float64}, Nothing))
precompile(JosephsonCircuits.calcinput!,(LinearAlgebra.Diagonal{ComplexF64, Vector{ComplexF64}}, Float64, Vector{ComplexF64}, Dict{Tuple{Int64, Int64}, Real}, Dict{Tuple{Int64, Int64}, Real}, Vector{Float64}, Nothing))
precompile(JosephsonCircuits.calcinput!,(LinearAlgebra.Diagonal{ComplexF64, Vector{ComplexF64}}, Float64, Matrix{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Dict{Tuple{Int64, Int64}, Number}, Vector{Float64}, Nothing))
precompile(JosephsonCircuits.calcinput!,(LinearAlgebra.Diagonal{ComplexF64, Vector{ComplexF64}}, Float64, Vector{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Dict{Tuple{Int64, Int64}, Number}, Vector{Float64}, Nothing))

precompile(JosephsonCircuits.calcLmean_inner,(Vector{Symbol}, Vector{Real}, Vector{Float64},))
precompile(JosephsonCircuits.calcLmean_inner,(Vector{Symbol}, Vector{Number}, Vector{ComplexF64}))
precompile(JosephsonCircuits.calcLmean,(Vector{Symbol}, Vector{Real},))

precompile(JosephsonCircuits.calcLb,(Vector{Symbol}, Matrix{Int64}, Vector{Real}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64))
precompile(JosephsonCircuits.calcLjb,(Vector{Symbol}, Matrix{Int64}, Vector{Real}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64))
precompile(JosephsonCircuits.calcMb,(Vector{Symbol}, Matrix{Int64}, Vector{Real}, Dict{Symbol, Int64}, Vector{Symbol}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64))
precompile(JosephsonCircuits.calcMb_inner,(Vector{Symbol}, Matrix{Int64}, Vector{Real}, Vector{Nothing}, Dict{Symbol, Int64}, Vector{Symbol}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64))
precompile(JosephsonCircuits.calcMb_inner,(Vector{Symbol}, Matrix{Int64}, Vector{Number}, Vector{Nothing}, Dict{Symbol, Int64}, Vector{Symbol}, Dict{Tuple{Int64, Int64}, Int64}, Int64, Int64))

precompile(JosephsonCircuits.calcnodematrix,(Vector{Symbol}, Matrix{Int64}, Vector{Number}, Int64, Int64, Symbol, Bool))
precompile(JosephsonCircuits.calcnodematrix,(Vector{Symbol}, Matrix{Int64}, Vector{Number}, Vector{ComplexF64}, Int64, Int64, Symbol, Bool))
precompile(JosephsonCircuits.calcnodematrix,(Vector{Symbol}, Matrix{Int64}, Vector{Real}, Vector{Float64}, Int64, Int64, Symbol, Bool))

precompile(JosephsonCircuits.calcoutput!,(Matrix{ComplexF64}, Matrix{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Dict{Tuple{Int64, Int64}, Number}, Vector{Float64}))
precompile(JosephsonCircuits.calcoutput!,(Vector{ComplexF64}, Vector{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Dict{Tuple{Int64, Int64}, Number}, Vector{Float64}))
precompile(JosephsonCircuits.calcoutput!,(Matrix{ComplexF64}, Matrix{ComplexF64}, Dict{Tuple{Int64, Int64}, Real}, Dict{Tuple{Int64, Int64}, Real}, Vector{Float64}, Nothing))
precompile(JosephsonCircuits.calcoutput!,(Vector{ComplexF64}, Vector{ComplexF64}, Dict{Tuple{Int64, Int64}, Real}, Dict{Tuple{Int64, Int64}, Real}, Vector{Float64}, Nothing))
precompile(JosephsonCircuits.calcoutput!,(Vector{ComplexF64}, Vector{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Dict{Tuple{Int64, Int64}, Number}, Vector{Float64}, Nothing))
precompile(JosephsonCircuits.calcoutput!,(Matrix{ComplexF64}, Matrix{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Dict{Tuple{Int64, Int64}, Number}, Vector{Float64}, Nothing))

precompile(JosephsonCircuits.calcphibports!,(Matrix{ComplexF64}, Matrix{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Int64))
precompile(JosephsonCircuits.calcphibports!,(Vector{ComplexF64}, Vector{ComplexF64}, Dict{Tuple{Int64, Int64}, Number}, Int64))
precompile(JosephsonCircuits.calcphibports!,(Matrix{ComplexF64}, Matrix{ComplexF64}, Dict{Tuple{Int64, Int64}, Real}, Int64))
precompile(JosephsonCircuits.calcphibports!,(Vector{ComplexF64}, Vector{ComplexF64}, Dict{Tuple{Int64, Int64}, Real}, Int64))

precompile(JosephsonCircuits.checknumbervector,(Vector{Symbol}, Vector{Number}))

precompile(JosephsonCircuits.componentdictionaryP,(Vector{Symbol},Matrix{Int64},Vector{Symbol},Vector{Number}))
precompile(JosephsonCircuits.componentdictionaryP,(Vector{Symbol}, Matrix{Int64}, Vector{Symbol}, Vector{Real}))
precompile(JosephsonCircuits.componentdictionaryR,(Vector{Symbol},Matrix{Int64},Vector{Symbol},Vector{Number}))
precompile(JosephsonCircuits.componentdictionaryR,(Vector{Symbol}, Matrix{Int64}, Vector{Symbol}, Vector{Real}))

precompile(JosephsonCircuits.freqsubst,(SparseArrays.SparseMatrixCSC{Nothing, Int64}, Vector{Float64}, Nothing))
precompile(JosephsonCircuits.freqsubst,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{Float64}, Nothing))
precompile(JosephsonCircuits.freqsubst,(SparseArrays.SparseMatrixCSC{Float64, Int64}, Vector{Float64}, Nothing))

precompile(JosephsonCircuits.pushval!,(Vector{ComplexF64},ComplexF64,Int64,Bool))
precompile(JosephsonCircuits.pushval!,(Vector{Float64}, Float64, Int64, Bool))

precompile(JosephsonCircuits.sparseaddmap,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}))
precompile(JosephsonCircuits.sparseaddmap,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{Int64, Int64}))
precompile(JosephsonCircuits.sparseaddmap,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, SparseArrays.SparseMatrixCSC{Float64, Int64}))

precompile(JosephsonCircuits.sparseadd!,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Int64, SparseArrays.SparseMatrixCSC{Int64, Int64}, Vector{UInt32}))
precompile(JosephsonCircuits.sparseadd!,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Int64, SparseArrays.SparseMatrixCSC{Float64, Int64}, Vector{UInt32}))
precompile(JosephsonCircuits.sparseadd!,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Int64, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Vector{UInt32}))
precompile(JosephsonCircuits.sparseadd!,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Int64, SparseArrays.SparseMatrixCSC{Nothing, Int64}, Vector{UInt32}))

precompile(JosephsonCircuits.sparseaddconj!,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Int64, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, LinearAlgebra.Diagonal{Float64, Vector{Float64}}, Vector{UInt32}, LinearAlgebra.Diagonal{Bool, Vector{Bool}}))
precompile(JosephsonCircuits.sparseaddconj!,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, Complex{Bool}, SparseArrays.SparseMatrixCSC{ComplexF64, Int64}, LinearAlgebra.Diagonal{Float64, Vector{Float64}}, Vector{UInt32}, LinearAlgebra.Diagonal{Bool, Vector{Bool}}))

precompile(JosephsonCircuits.symbolicindices,(SparseArrays.SparseMatrixCSC{Nothing, Int64},))
precompile(JosephsonCircuits.symbolicindices,(SparseArrays.SparseMatrixCSC{ComplexF64, Int64},))
precompile(JosephsonCircuits.symbolicindices,(SparseArrays.SparseMatrixCSC{Float64, Int64},))

precompile(JosephsonCircuits.valuevectortonumber,(Vector{Union{Int64, Symbol, ComplexF64}}, Dict{Symbol, ComplexF64}))
precompile(JosephsonCircuits.valuevectortonumber,(Vector{Union{Int64, Symbol, ComplexF64}}, Dict{Symbol, Float64}))


