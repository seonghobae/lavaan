# main user-visible cfa/sem/growth functions 
#
# initial version: YR 25/03/2009
# added lavoptions YR 02/08/2010
# major revision: YR 9/12/2010: - new workflow (since 0.4-5)
#                               - merge cfa/sem/growth functions
# YR 25/02/2012: changed data slot (from list() to S4); data@X contains data

lavaan <- function(# user-specified model: can be syntax, parameter Table, ...
                   model              = NULL,
                   data               = NULL,  # second argument, most used!
                   model.type         = "sem",
                
                   # model modifiers
                   meanstructure      = "default",
                   int.ov.free        = FALSE,
                   int.lv.free        = FALSE,
                   conditional.x      = "default", # or FALSE?
                   fixed.x            = "default", # or FALSE?
                   orthogonal         = FALSE,
                   std.lv             = FALSE,
                   parameterization   = "default",

                   auto.fix.first     = FALSE,
                   auto.fix.single    = FALSE,
                   auto.var           = FALSE,
                   auto.cov.lv.x      = FALSE,
                   auto.cov.y         = FALSE,
                   auto.th            = FALSE,
                   auto.delta         = FALSE,
                   
                   # full data
                   std.ov             = FALSE,
                   missing            = "default",
                   ordered            = NULL,

                   # summary data
                   sample.cov         = NULL,
                   sample.cov.rescale = "default",
                   sample.mean        = NULL,
                   sample.nobs        = NULL,
                   ridge              = 1e-5,

                   # multiple groups
                   group              = NULL,
                   group.label        = NULL,
                   group.equal        = '',
                   group.partial      = '',
                   group.w.free       = FALSE,

                   # clusters
                   cluster            = NULL,
             
                   # constraints
                   constraints        = '',

                   # estimation
                   estimator          = "default",
                   likelihood         = "default",
                   link               = "default",
                   information        = "default",
                   se                 = "default",
                   test               = "default",
                   bootstrap          = 1000L,
                   mimic              = "default",
                   representation     = "default",
                   do.fit             = TRUE,
                   control            = list(),
                   WLS.V              = NULL,
                   NACOV              = NULL,

                   # zero values
                   zero.add           = "default",
                   zero.keep.margins  = "default",
                   zero.cell.warn     = TRUE,

                   # starting values
                   start              = "default",

                   # full slots from previous fits
                   slotOptions        = NULL,
                   slotParTable       = NULL,
                   slotSampleStats    = NULL,
                   slotData           = NULL,
                   slotModel          = NULL,
                   slotCache          = NULL,
  
                   # verbosity
                   verbose            = FALSE,
                   warn               = TRUE,
                   debug              = FALSE
                  )
{
    # start timer
    start.time0 <- start.time <- proc.time()[3]; timing <- list()

    # 0a. store call
    mc  <- match.call()









    ###################################
    #### 1. ov.names + categorical ####
    ###################################
    # 1a. get ov.names and ov.names.x (per group) -- needed for lavData()
    if(!is.null(slotParTable)) {
        FLAT <- slotParTable
    } else if(is.character(model)) {
        FLAT <- lavParseModelString(model)
    } else if(is.list(model)) {
        # two possibilities: either model is already lavaanified
        # or it is something else...

        # look for the bare minimum columns: lhs - op -
        if(!is.null(model$lhs) && !is.null(model$op)  &&
           !is.null(model$rhs) && !is.null(model$free)) {

            # ok, we have something that looks like a parameter table
            # FIXME: we need to check for redundant arguments 
            # (but if cfa/sem was used, we can not trust the call)
            # redundant <- c("meanstructure", "int.ov.free", "int.lv.free",
            #        "fixed.x", "orthogonal", "std.lv", "parameterization",
            #        "auto.fix.first", "auto.fix.single", "auto.var",
            #        "auto.cov.lv.x", "auto.cov.y", "auto.th", "auto.delta")
            FLAT <- model
        } else {
            bare.minimum <- c("lhs", "op", "rhs", "free")
            missing.idx <- is.na(match(bare.minimum, names(model)))
            missing.txt <- paste(bare.minimum[missing.idx], collapse = ", ")
            stop("lavaan ERROR: model is a list, but not a parameterTable?",
                 "\n  lavaan  NOTE: ", 
                 "missing column(s) in parameter table: [", missing.txt, "]")
        }
    }

    if(max(FLAT$group) < 2L) { # same model for all groups 
        ov.names   <- vnames(FLAT, type="ov")
        ov.names.y <- vnames(FLAT, type="ov.nox")
        ov.names.x <- vnames(FLAT, type="ov.x")
    } else { # different model per group
        ov.names <- lapply(1:max(FLAT$group),
                           function(x) vnames(FLAT, type="ov", group=x))
        ov.names.y <- lapply(1:max(FLAT$group),
                           function(x) vnames(FLAT, type="ov.nox", group=x))
        ov.names.x <- lapply(1:max(FLAT$group),
                           function(x) vnames(FLAT, type="ov.x", group=x))
    }

    # 1b categorical variables? -- needed for lavoptions
    if(any(FLAT$op == "|")) {
        categorical <- TRUE
        # just in case, add lhs variables names to "ordered"
        ordered <- unique(c(ordered, lavNames(FLAT, "ov.ord")))
    } else if(!is.null(data) && length(ordered) > 0L) {
        categorical <- TRUE
    } else if(is.data.frame(data) && 
              lav_dataframe_check_ordered(frame=data, ov.names=ov.names.y)) {
        categorical <- TRUE
    } else {
        categorical <- FALSE
    }

    # 1c meanstructure? -- needed for lavoptions
    if(any(FLAT$op == "~1")) {
        meanstructure <- TRUE
    }









    #######################
    #### 2. lavoptions ####
    #######################
    #opt <- modifyList(formals(lavaan), as.list(mc)[-1])
    # force evaluation of `language` and/or `symbol` arguments
    #opt <- lapply(opt, function(x) if(typeof(x) %in% c("language", "symbol")) 
    #                                   eval(x, parent.frame()) else x)
    if(!is.null(slotOptions)) {
        lavoptions <- slotOptions
    } else {
        opt <- list(model = model, model.type = model.type,
            meanstructure = meanstructure, 
            int.ov.free = int.ov.free, int.lv.free = int.lv.free, 
            conditional.x = conditional.x, fixed.x = fixed.x, 
            orthogonal = orthogonal, std.lv = std.lv, 
            parameterization = parameterization,
            auto.fix.first = auto.fix.first, auto.fix.single = auto.fix.single,
            auto.var = auto.var, auto.cov.lv.x = auto.cov.lv.x, 
            auto.cov.y = auto.cov.y, auto.th = auto.th, 
            auto.delta = auto.delta, missing = missing, 
            group = group, categorical = categorical,
            group.equal = group.equal, group.partial = group.partial, 
            group.w.free = group.w.free,
            constraints = constraints,
            estimator = estimator, likelihood = likelihood, link = link,
            sample.cov.rescale = sample.cov.rescale,
            information = information, se = se, test = test, 
            bootstrap = bootstrap, mimic = mimic,
            zero.add = zero.add, zero.keep.margins = zero.keep.margins,
            zero.cell.warn = zero.cell.warn,
            representation = representation, do.fit = do.fit, verbose = verbose,
            warn = warn, debug = debug)
        lavoptions <- lav_options_set(opt)
    }
    timing$InitOptions <- (proc.time()[3] - start.time)
    start.time <- proc.time()[3]

    # some additional checks for estimator="PML"
    if(lavoptions$estimator == "PML") {
        ovy <- unique( unlist(ov.names.y) )
        ovx <- unique( unlist(ov.names.x) )
        if(!is.null(slotData)) {
            ov.types <- slotData@ov$type[ slotData@ov$name %in% ovy ]
        } else {
            ov.types <- lav_dataframe_check_vartype(data, ov.names=ov.names.y)
        }
        # ordered argument?
        if(length(ordered) > 0L) {
            ord.idx <- which(ovy %in% ordered)
            ov.types[ord.idx] <- "ordered"
        }
        # 0. at least some variables must be ordinal
        if(!any(ov.types == "ordered")) {
            stop("lavaan ERROR: estimator=\"PML\" is only available if some variables are ordinal")
        }
        # 1. all variables must be ordinal (for now)
        #    (the mixed continuous/ordinal case will be added later)
        if(any(ov.types != "ordered")) {
            stop("lavaan ERROR: estimator=\"PML\" can not handle mixed continuous and ordinal data (yet)")
        }
        
        # 2. we can not handle exogenous covariates yet
        if(length(ovx) > 0L) {
            stop("lavaan ERROR: estimator=\"PML\" can not handle exogenous covariates (yet)")
        }
    }









    #####################
    #### 3. lavdata  ####
    #####################
    if(!is.null(slotData)) {
        lavdata <- slotData
    } else {
        if(lavoptions$conditional.x) {
            ov.names <- ov.names.y
        }
        lavdata <- lavData(data        = data,
                           group       = group,
                           group.label = group.label,
                           ov.names    = ov.names,
                           ordered     = ordered,
                           ov.names.x  = ov.names.x,
                           std.ov      = std.ov,
                           missing     = lavoptions$missing,
                           sample.cov  = sample.cov,
                           sample.mean = sample.mean,
                           sample.nobs = sample.nobs,
                           warn        = lavoptions$warn)
    }
    # what have we learned from the data?
    if(lavdata@data.type == "none") {
        do.fit <- FALSE; start <- "simple"
        lavoptions$se <- "none"; lavoptions$test <- "none"
    } else if(lavdata@data.type == "moment") {
        # catch here some options that will not work with moments
        if(lavoptions$se == "bootstrap") {
            stop("lavaan ERROR: bootstrapping requires full data")
        }
        if(estimator %in% c("MLM", "MLMV", "MLMVS", "MLR", 
                            "ULSM", "ULSMV", "ULSMVS") && is.null(NACOV)) {
            stop("lavaan ERROR: estimator ", estimator, " requires full data or user-provided NACOV")
        }
        if(estimator %in% c("WLS", "WLSM", "WLSMV", "WLSMVS", "DWLS") &&
           is.null(WLS.V)) {
            stop("lavaan ERROR: estimator ", estimator, " requires full data or user-provided WLS.V") 
        }
    }
    timing$InitData <- (proc.time()[3] - start.time)
    start.time <- proc.time()[3]
    if(debug) print(str(lavdata))









    ########################
    #### 4. lavpartable ####
    ########################
    if(!is.null(slotParTable)) {
        lavpartable <- slotParTable
    } else if(is.character(model)) {
        # check FLAT before we proceed
        if(debug) print(as.data.frame(FLAT))
        # catch ~~ of fixed.x covariates if fixed.x = TRUE
        if(lavoptions$fixed.x) {
            tmp <- vnames(FLAT, type = "ov.x", ov.x.fatal = TRUE)
        }

        lavpartable <- 
            lavaanify(model            = FLAT,
                      meanstructure    = lavoptions$meanstructure, 
                      int.ov.free      = lavoptions$int.ov.free,
                      int.lv.free      = lavoptions$int.lv.free,
                      orthogonal       = lavoptions$orthogonal, 
                      conditional.x    = lavoptions$conditional.x,
                      fixed.x          = lavoptions$fixed.x,
                      std.lv           = lavoptions$std.lv,
                      parameterization = lavoptions$parameterization,
                      constraints      = constraints,

                      auto.fix.first   = lavoptions$auto.fix.first,
                      auto.fix.single  = lavoptions$auto.fix.single,
                      auto.var         = lavoptions$auto.var,
                      auto.cov.lv.x    = lavoptions$auto.cov.lv.x,
                      auto.cov.y       = lavoptions$auto.cov.y,
                      auto.th          = lavoptions$auto.th,
                      auto.delta       = lavoptions$auto.delta,

                      varTable         = lavdata@ov,
                      ngroups          = lavdata@ngroups,
                      group.equal      = lavoptions$group.equal, 
                      group.partial    = lavoptions$group.partial,
                      group.w.free     = lavoptions$group.w.free,
                      debug            = lavoptions$debug,
                      warn             = lavoptions$warn,

                      as.data.frame.   = FALSE)

    } else if(is.list(model)) {
        # we already checked this when creating FLAT
        # but we may need to complete it
        lavpartable <- as.list(model) # in case model is a data.frame
        # complete table
        lavpartable <- lav_partable_complete(lavpartable)
    } else {
        stop("lavaan ERROR: model [type = ", class(model), 
             "] is not of type character or list")
    }
    if(debug) print(as.data.frame(lavpartable))

    # at this point, we should check if the partable is complete
    # or not; this is especially relevant if the lavaan() function
    # was used, but the user has forgotten some variances/intercepts...
    check <- lav_partable_check(lavpartable, categorical = categorical,
                                warn = TRUE)

    # 4b. get partable attributes
    lavpta <- lav_partable_attributes(lavpartable)
    timing$ParTable <- (proc.time()[3] - start.time)
    start.time <- proc.time()[3]







    ###########################
    #### 5. lavsamplestats ####
    ##########################
    if(!is.null(slotSampleStats)) {
        lavsamplestats <- slotSampleStats
    } else if(lavdata@data.type == "full") {
        lavsamplestats <- lav_samplestats_from_data(
                       lavdata       = lavdata,
                       missing       = lavoptions$missing,
                       rescale       = 
                           (lavoptions$estimator %in% c("ML","REML") &&
                            lavoptions$likelihood == "normal"),
                       estimator     = lavoptions$estimator,
                       mimic         = lavoptions$mimic,
                       meanstructure = lavoptions$meanstructure,
                       conditional.x = lavoptions$conditional.x,
                       fixed.x       = lavoptions$fixed.x,
                       group.w.free  = lavoptions$group.w.free,
                       missing.h1    = (lavoptions$missing != "listwise"),
                       WLS.V             = WLS.V,
                       NACOV             = NACOV,
                       ridge             = ridge,
                       optim.method      = 
                           ifelse(!is.null(control$cor.optim.method), 
                                           control$cor.optim.method, "nlminb"),
                       zero.add          = lavoptions$zero.add,
                       zero.keep.margins = lavoptions$zero.keep.margins,
                       zero.cell.warn    = lavoptions$zero.cell.warn,
                       debug             = lavoptions$debug,
                       verbose           = lavoptions$verbose)
                                                 
    } else if(lavdata@data.type == "moment") {
        lavsamplestats <- lav_samplestats_from_moments(
                           sample.cov    = sample.cov,
                           sample.mean   = sample.mean,
                           sample.nobs   = sample.nobs,
                           ov.names      = lavpta$vnames$ov,
                           estimator     = lavoptions$estimator,
                           mimic         = lavoptions$mimic,
                           meanstructure = lavoptions$meanstructure,
                           group.w.free  = lavoptions$group.w.free,
                           WLS.V         = WLS.V,
                           NACOV         = NACOV,
                           ridge         = ridge,
                           rescale       = lavoptions$sample.cov.rescale)
    } else {
        # no data
        th.idx <- vector("list", length=lavdata@ngroups)
        for(g in 1:lavdata@ngroups) {
            th.idx[[g]] <- lav_partable_ov_idx(lavpartable, type="th")
        }
        lavsamplestats <- new("lavSampleStats", ngroups=lavdata@ngroups,
                                 nobs=as.list(rep(0L, lavdata@ngroups)),
                                 cov.x=vector("list",length=lavdata@ngroups),
                                 th.idx=th.idx,
                                 missing.flag=FALSE)
    }
    timing$Sample <- (proc.time()[3] - start.time)
    start.time <- proc.time()[3]
    if(debug) print(str(lavsamplestats))









    #####################
    #### 6. lavstart ####
    #####################
    if(!is.null(slotModel)) {
        lavmodel <- slotModel
        # FIXME
        #lavaanStart <- lav_model_get_parameters(lavmodel, type="user")
        #lavpartable$start <- lavaanStart
        timing$Start <- (proc.time()[3] - start.time)
        start.time <- proc.time()[3]
        timing$Model <- (proc.time()[3] - start.time)
        start.time <- proc.time()[3]
    } else {
        # check if we have provide a full parameter table as model= input
        if(!is.null(lavpartable$est) && start == "default") {
            # check if all 'est' values look ok
            # this is not the case, eg, if partables have been merged eg, as
            # in semTools' auxiliary() function

            # check for zero free variances and NA values
            zero.idx <- which(lavpartable$free > 0L &
                              lavpartable$op == "~~" &
                              lavpartable$lhs == lavpartable$rhs &
                              lavpartable$est == 0)

            if(length(zero.idx) > 0L || any(is.na(lavpartable$est))) {
                lavpartable$start <- lav_start(start.method = start,
                                       lavpartable     = lavpartable,
                                       lavsamplestats  = lavsamplestats,
                                       model.type   = lavoptions$model.type,
                                       conditional.x = lavoptions$conditional.x,
                                       mimic        = lavoptions$mimic,
                                       debug        = lavoptions$debug)
            } else {
                lavpartable$start <- lavpartable$est
            }
        } else {
            lavpartable$start <- lav_start(start.method = start,
                                       lavpartable     = lavpartable, 
                                       lavsamplestats  = lavsamplestats,
                                       model.type   = lavoptions$model.type,
                                       conditional.x = lavoptions$conditional.x,
                                       mimic        = lavoptions$mimic,
                                       debug        = lavoptions$debug)
        }
        timing$Start <- (proc.time()[3] - start.time)
        start.time <- proc.time()[3]









    #####################
    #### 7. lavmodel ####
    #####################
        lavmodel <- 
            lav_model(lavpartable      = lavpartable,
                      representation   = lavoptions$representation,
                      conditional.x    = lavoptions$conditional.x,
                      th.idx           = lavsamplestats@th.idx,
                      parameterization = lavoptions$parameterization,
                      link             = lavoptions$link,
                      control          = control,
                      debug            = lavoptions$debug)
        timing$Model <- (proc.time()[3] - start.time)
        start.time <- proc.time()[3]
  
        # if no data, call lav_model_set_parameters once (for categorical case)
        if(lavdata@data.type == "none" && lavmodel@categorical) {
            lavmodel <- 
                lav_model_set_parameters(lavmodel = lavmodel, 
                                         x = lav_model_get_parameters(lavmodel), 
                                         estimator =lavoptions$estimator)
        }
    }









    #####################
    #### 8. lavcache ####
    #####################
    if(!is.null(slotCache)) {
        lavcache <- slotCache
    } else {
        # prepare cache -- stuff needed for estimation, but also post-estimation
        lavcache <- vector("list", length=lavdata@ngroups)
        if(lavoptions$estimator == "PML") {
            TH <- computeTH(lavmodel)
            BI <- lav_tables_pairwise_freq_cell(lavdata)
            for(g in 1:lavdata@ngroups) {
                if(is.null(BI$group) || max(BI$group) == 1L) {
                    bifreq <- BI$obs.freq
                    binobs  <- BI$nobs
                } else {
                    idx <- which(BI$group == g)
                    bifreq <- BI$obs.freq[idx]
                    binobs  <- BI$nobs[idx]
                }
                LONG  <- LongVecInd(no.x               = ncol(lavdata@X[[g]]),
                                   all.thres          = TH[[g]],
                                   index.var.of.thres = lavmodel@th.idx[[g]])
                lavcache[[g]] <- list(bifreq = bifreq,
                                      nobs   = binobs,
                                     LONG   = LONG)
            }
        }
        # copy response patterns to cache -- FIXME!! (data not included 
        # in Model only functions)
        if(lavdata@data.type == "full" && !is.null(lavdata@Rp[[1L]])) {
            for(g in 1:lavdata@ngroups) {
                lavcache[[g]]$pat <- lavdata@Rp[[g]]$pat
            }
        }
    }

    # If estimator = MML, store Gauss-Hermite nodes/weights
    if(lavoptions$estimator == "MML") {
        if(!is.null(control$nGH)) {
            nGH <- control$nGH
        } else {
            nGH <- 21L
        }
        for(g in 1:lavdata@ngroups) {
            # count only the ones with non-normal indicators
            #nfac <- lavpta$nfac.nonnormal[[g]]
            nfac <- lavpta$nfac[[g]]
            lavcache[[g]]$GH <- 
                lav_gauss_hermite_xw_dnorm(n=nGH, revert=FALSE, ndim = nfac)
            #lavcache[[g]]$DD <- lav_model_gradient_DD(lavmodel, group = g)
        }
    }









    ############################
    #### 10. est + lavoptim ####
    ############################
    x <- NULL
    if(do.fit && lavoptions$estimator != "none" && 
       lavmodel@nx.free > 0L) {

        x <- lav_model_estimate(lavmodel        = lavmodel,
                                lavsamplestats  = lavsamplestats,
                                lavdata         = lavdata,
                                lavoptions      = lavoptions,
                                lavcache        = lavcache)
        lavmodel <- lav_model_set_parameters(lavmodel, x = x,
                                             estimator = lavoptions$estimator)

        # store parameters in @ParTable$est
        lavpartable$est <- lav_model_get_parameters(lavmodel = lavmodel,
                                                    type = "user", extra = TRUE)

        if(!is.null(attr(x, "con.jac"))) 
            lavmodel@con.jac <- attr(x, "con.jac")
        if(!is.null(attr(x, "con.lambda")))
            lavmodel@con.lambda <- attr(x, "con.lambda")
        # check if model has converged or not
        if(!attr(x, "converged") && lavoptions$warn) {
           warning("lavaan WARNING: model has NOT converged!")
        }
    } else {
        x <- numeric(0L)
        attr(x, "iterations") <- 0L; attr(x, "converged") <- FALSE
        attr(x, "control") <- control
        attr(x, "fx") <- 
            lav_model_objective(lavmodel = lavmodel, 
                lavsamplestats = lavsamplestats, lavdata = lavdata, 
                lavcache = lavcache, estimator = lavoptions$estimator)

        lavpartable$est <- lavpartable$start
    }

    # should we fake/force convergence? (eg. to enforce the
    # computation of a test statistic)
    if(!is.null(control$optim.force.converged) &&
       control$optim.force.converged) {
        attr(x, "converged") <- TRUE
    }

    # store optimization info in lavoptim
    lavoptim <- list()
    lavoptim$iterations <- attr(x, "iterations")
    lavoptim$converged  <- attr(x, "converged")
    fx.copy <- fx <- attr(x, "fx"); attributes(fx) <- NULL
    lavoptim$fx         <- fx
    lavoptim$fx.group   <- attr(fx.copy, "fx.group")
    if(!is.null(attr(fx.copy, "logl.group"))) {
        lavoptim$logl.group <- attr(fx.copy, "logl.group")
        lavoptim$logl       <- sum(lavoptim$logl.group)
    } else {
        lavoptim$logl.group <- as.numeric(NA)
        lavoptim$logl       <- as.numeric(NA)
    }
    lavoptim$control        <- attr(x, "control")









    ########################
    #### 11. lavimplied ####
    ########################
    lavimplied <- lav_model_implied(lavmodel)

    timing$Estimate <- (proc.time()[3] - start.time)
    start.time <- proc.time()[3]










    ###############################
    #### 12. lavvcov + lavboot ####
    ###############################
    VCOV <- NULL
    if(lavoptions$se != "none" && lavoptions$se != "external" && 
       lavmodel@nx.free > 0L && attr(x, "converged")) {
        if(verbose) cat("Computing VCOV for se =", lavoptions$se, "...")
        VCOV <- lav_model_vcov(lavmodel        = lavmodel,
                               lavsamplestats  = lavsamplestats,
                               lavoptions      = lavoptions,
                               lavdata         = lavdata,
                               lavpartable     = lavpartable,
                               lavcache        = lavcache)
        if(verbose) cat(" done.\n")
    }

    # extract bootstrap results (if any)
    if(!is.null(attr(VCOV, "BOOT.COEF"))) {
        lavboot <- list()
        lavboot$coef <- attr(VCOV, "BOOT.COEF")
    } else {
        lavboot <- list()  
    }

    # store VCOV in vcov
    # strip all attributes but 'dim'
    tmp.attr <- attributes(VCOV)
    VCOV1 <- VCOV
    attributes(VCOV1) <- tmp.attr["dim"]
    lavvcov <- list(se = lavoptions$se, information = lavoptions$information,
                    vcov = VCOV1)

    # store se in partable
    if(lavoptions$se != "external") {
        lavpartable$se <- lav_model_vcov_se(lavmodel = lavmodel, 
                                            lavpartable = lavpartable,
                                            VCOV = VCOV, 
                                            BOOT = lavboot$coef)
    } else {
        if(is.null(lavpartable$se)) {
            lavpartable$se <- lav_model_vcov_se(lavmodel = lavmodel, 
                                                lavpartable = lavpartable,
                                                VCOV = NULL, BOOT = NULL)
            warning("lavaan WARNING: se = \"external\" but parameter table does not contain a `se' column")
        }
    }

    timing$VCOV <- (proc.time()[3] - start.time)
    start.time <- proc.time()[3]









    #####################
    #### 13. lavtest ####
    #####################
    TEST <- NULL
    if(lavoptions$test != "none" && attr(x, "converged")) {
        if(verbose) cat("Computing TEST for test =", lavoptions$test, "...")
        TEST <- lav_model_test(lavmodel            = lavmodel,
                               lavpartable         = lavpartable,
                               lavsamplestats      = lavsamplestats,
                               lavoptions          = lavoptions,
                               x                   = x,
                               VCOV                = VCOV,
                               lavdata             = lavdata,
                               lavcache            = lavcache)
        if(verbose) cat(" done.\n")
    } else {
        TEST <- list(list(test="none", stat=NA, 
                     stat.group=rep(NA, lavdata@ngroups), df=NA, 
                     refdistr="unknown", pvalue=NA))
    }

    # store test in lavtest
    lavtest <- TEST

    timing$TEST <- (proc.time()[3] - start.time)
    start.time <- proc.time()[3]










    ####################
    #### 14. lavfit ####
    ####################
    lavfit <- lav_model_fit(lavpartable = lavpartable, 
                            lavmodel    = lavmodel,
                            x           = x, 
                            VCOV        = VCOV,
                            TEST        = TEST)
    timing$total <- (proc.time()[3] - start.time0)









    ####################
    #### 15. lavaan ####
    ####################
    lavaan <- new("lavaan",
                  call         = mc,                  # match.call
                  timing       = timing,              # list
                  Options      = lavoptions,          # list
                  ParTable     = lavpartable,         # list
                  pta          = lavpta,              # list
                  Data         = lavdata,             # S4 class
                  SampleStats  = lavsamplestats,      # S4 class
                  Model        = lavmodel,            # S4 class
                  Cache        = lavcache,            # list
                  Fit          = lavfit,              # S4 class
                  boot         = lavboot,             # list
                  optim        = lavoptim,            # list
                  implied      = lavimplied,          # list
                  vcov         = lavvcov,             # list
                  test         = lavtest,             # list
                  external     = list()               # empty list
                 )



    # post-fitting check
    if(lavTech(lavaan, "converged")) {
        lavInspect(lavaan, "post.check")
    }

    lavaan
}



# cfa + sem
cfa <- sem <- function(model = NULL, data = NULL,
    meanstructure = "default", 
    conditional.x = "default", fixed.x = "default",
    orthogonal = FALSE, std.lv = FALSE, 
    parameterization = "default", std.ov = FALSE,
    missing = "default", ordered = NULL, 
    sample.cov = NULL, sample.cov.rescale = "default", sample.mean = NULL,
    sample.nobs = NULL, ridge = 1e-5,
    group = NULL, group.label = NULL,
    group.equal = "", group.partial = "", group.w.free = FALSE,
    cluster = NULL, constraints = "",
    estimator = "default", likelihood = "default", link = "default",
    information = "default", se = "default", test = "default",
    bootstrap = 1000L, mimic = "default", representation = "default",
    do.fit = TRUE, control = list(), WLS.V = NULL, NACOV = NULL,
    zero.add = "default", zero.keep.margins = "default", 
    zero.cell.warn = TRUE, start = "default",
    verbose = FALSE, warn = TRUE, debug = FALSE) {

    mc <- match.call()

    mc$model.type      = as.character( mc[[1L]] )
    if(length(mc$model.type) == 3L) mc$model.type <- mc$model.type[3L]
    mc$int.ov.free     = TRUE
    mc$int.lv.free     = FALSE
    mc$auto.fix.first  = !std.lv
    mc$auto.fix.single = TRUE
    mc$auto.var        = TRUE
    mc$auto.cov.lv.x   = TRUE
    mc$auto.cov.y      = TRUE
    mc$auto.th         = TRUE
    mc$auto.delta      = TRUE
    mc[[1L]] <- quote(lavaan::lavaan)

    eval(mc, parent.frame())
}

# simple growth models
growth <- function(model = NULL, data = NULL,
    conditional.x = "default", fixed.x = "default",
    orthogonal = FALSE, std.lv = FALSE, 
    parameterization = "default", std.ov = FALSE,
    missing = "default", ordered = NULL, 
    sample.cov = NULL, sample.cov.rescale = "default", sample.mean = NULL,
    sample.nobs = NULL, ridge = 1e-5,
    group = NULL, group.label = NULL,
    group.equal = "", group.partial = "", group.w.free = FALSE,
    cluster = NULL, constraints = "",
    estimator = "default", likelihood = "default", link = "default",
    information = "default", se = "default", test = "default",
    bootstrap = 1000L, mimic = "default", representation = "default",
    do.fit = TRUE, control = list(), WLS.V = NULL, NACOV = NULL,
    zero.add = "default", zero.keep.margins = "default", 
    zero.cell.warn = TRUE, start = "default",
    verbose = FALSE, warn = TRUE, debug = FALSE) {

    mc <- match.call()

    mc$model.type      = "growth"
    mc$int.ov.free     = FALSE
    mc$int.lv.free     = TRUE
    mc$auto.fix.first  = !std.lv
    mc$auto.fix.single = TRUE
    mc$auto.var        = TRUE
    mc$auto.cov.lv.x   = TRUE
    mc$auto.cov.y      = TRUE
    mc$auto.th         = TRUE
    mc$auto.delta      = TRUE
    mc[[1L]] <- quote(lavaan::lavaan)

    eval(mc, parent.frame())
}
