library(lavaan)
library(semPlot)
library(glmnet)

library(glmnet)
source(paste0(getwd(), "/code/lav_predict_y_reg.R"))
source(paste0(getwd(), "/code/cv_lav_predict_y.R"))
source(paste0(getwd(), "/code/lav_data_patterns.R"))
source(paste0(getwd(), "/code/lav_data.R"))
source(paste0(getwd(), "/code/lav_dataframe.R"))

data(PoliticalDemocracy)
pd <- PoliticalDemocracy
colnames(PoliticalDemocracy) = c("z1", "z2", "z3", "z4", "y1", "y2", "y3", "y4", "x1", "x2", "x3")
head(PoliticalDemocracy)

model0 <- '
  # latent variable definitions
  ind60 =~ x1 + x2 + x3
  dem60 =~ z1 + z2 + z3 + z4
  dem65 =~ y1 + y2 + y3 + y4
  # regressions
  dem60 ~ ind60
  dem65 ~ ind60 + dem60
  # residual correlations
  z1 ~~ y1
  z2 ~~ z4 + y2
  z3 ~~ y3
  z4 ~~ y4
  y2 ~~ y4
'

fit <- sem(model0, data = PoliticalDemocracy, meanstructure = TRUE, warn = FALSE)
semPaths(fit, title = FALSE, intercepts = FALSE, residuals = FALSE)

# library(regsem)
# extractMatrices(fit)$S
# regsem.res <- cv_regsem(fit, metric = "rmsea", pars_pen = c("loadings"), lambda.start = 0, jump = .03, n.lambda = 20)
# summary(regsem.res)
# plot(regsem.res, show.minimum="BIC")
# regsem.res$fits

# Repeated 10 fold CV for varying models

model <- '
  # latent variable definitions
  ind60 =~ x1 + x2 + x3
  dem60 =~ z1 + z2 + z3 + z4
  dem65 =~ y1 + y2 + y3 + y4
  # regressions
  dem60 ~ ind60
  dem65 ~ ind60 + dem60
  # residual correlations
  z1 ~~ y1
  z2 ~~ z4 + y2
  z3 ~~ y3
  z4 ~~ y4
  y2 ~~ y4
'
names(PoliticalDemocracy)
xnames = colnames(PoliticalDemocracy)[-c(5,6,7,8)]
ynames = colnames(PoliticalDemocracy)[c(5,6,7,8)]

set.seed(1234)
repeats = 100
PE = data.frame(repetition = rep(1:repeats, each = 4), 
                model = rep(1:4, repeats), 
                pe = rep(0, 4 * repeats))

folds = rep(1:10, length.out = 75)
t = 0
for (r in 1:repeats) {
  yhat1 = yhat2 = yhat3 = yhat4 = matrix(NA, 75, 4)
  folds = sample(folds)
  
  print(paste("Iteration:", r))
  
  for(k in 1:10){
    t = t + 1
    idx = which(folds == k)

    # Fit SEM model
    # fit <- sem(model, data = PoliticalDemocracy[-idx, ], meanstructure = TRUE, warn = FALSE)
    fit <- sem(model, data = PoliticalDemocracy[-idx, ], meanstructure = TRUE)
    
    # RO-SEM Approach
    reg.results <- cv.lavPredictYReg(
      fit,
      PoliticalDemocracy[-idx, ],
      xnames,
      ynames,
      n.folds = 10,
      lambda.seq = seq(from = .6, to = 2.5, by = .1)
    )
    lambda <- reg.results$lambda.min
    print(paste("lambda.min: ",lambda))
    yhat1[idx, ] = lavPredictYreg(fit, newdata = PoliticalDemocracy[idx, ], xnames = xnames, ynames = ynames, lambda = lambda)
    
    # OOS Approach
    yhat2[idx, ] = lavPredictY(fit, newdata = PoliticalDemocracy[idx, ], xnames = xnames, ynames = ynames)
    
    # Regularized regression approach (poor model fit)
    # cv.out <- cv.glmnet(
    #   as.matrix(PoliticalDemocracy[-idx, xnames]),
    #   as.matrix(PoliticalDemocracy[-idx, ynames]),
    #   alpha = 0,
    #   family = "mgaussian",
    #   lambda = seq(from = 0, to = 2, by = .1)
    # )
    # 
    # out <- glmnet(
    #   as.matrix(PoliticalDemocracy[-idx, xnames]),
    #   as.matrix(PoliticalDemocracy[-idx, ynames]),
    #   alpha = 0,
    #   lambda = cv.out$lambda.min,
    #   family = "mgaussian"
    # )
    # 
    # yhat3 <- predict(out, newx = as.matrix(PoliticalDemocracy[idx, xnames]), s = cv.out$lambda.min)

    # linear regression model
    fit = lm(cbind(y1,y2,y3,y4) ~ ., data = PoliticalDemocracy[-idx, ])
    yhat3[idx, ]= predict(fit, newdata = PoliticalDemocracy[idx, ])
    
    
  }# end folds

  pe1 = sqrt(sum((PoliticalDemocracy[, ynames] - yhat1)^2)/300)
  pe2 = sqrt(sum((PoliticalDemocracy[, ynames] - yhat2)^2)/300)
  pe3 = sqrt(sum((PoliticalDemocracy[, ynames] - yhat3)^2)/300)
  pe4 = sqrt(sum((PoliticalDemocracy[, ynames] - yhat4)^2)/300)
  PE$pe[((r-1)*4 + 1): (r*4)] = c(pe1, pe2, pe3, pe4)
} # end repetitions

library(ggplot2)
PE$model = as.factor(PE$model)
# saveRDS(PE, file = "outputs/political-dem-xval.rds")
# PE <- readRDS(file = "outputs/political-dem-xval.rds")


png(filename = "documents/figures/Fig8.png", width = 800, height = 640)
ggplot(PE[PE$model == 1 | PE$model == 2 | PE$model == 3,], aes(x = factor(model), y = pe, fill = factor(model))) +
  geom_boxplot(fill = "grey80", aes(group = factor(model))) +  
  geom_jitter(width = 0.05, height = 0, colour = rgb(0, 0, 0, 0.5), size = 3) +  
  xlab("Prediction Method") + 
  ylab("RMSEp") + 
  scale_x_discrete(labels = c("RO-SEM", "OOS", "MLR")) +  
  theme_minimal(base_size = 14) +  
  theme(
    legend.position = "none", 
    axis.title.x = element_text(size = 25, margin = margin(t = 10)),  
    axis.text.x = element_text(size = 25),  
    axis.ticks.x = element_blank(),  
    axis.title.y = element_text(size = 25),  
    axis.text.y = element_text(size = 25),  
    panel.grid.major.x = element_blank(),  # Remove vertical major grid lines
    panel.grid.minor.x = element_blank(),  # Remove vertical minor grid lines
    panel.grid.major.y = element_line(size = 0.5, colour = "grey85"),  # Keep horizontal lines for readability
    panel.grid.minor.y = element_blank()  # No minor grid lines
  ) +
  scale_fill_grey(start = 0.5, end = 0.8)
dev.off()

t.test(pe ~ model, data = PE[PE$model == 2 | PE$model == 1,])


