compute_pl_eff <- function(p_l, p_d, alpha_dep) {
  p_d_safe <- ifelse(is.finite(p_d) & p_d > 0, p_d, 1.0)
  w1 <- pmin(0.05, p_d_safe) / p_d_safe
  w2 <- pmin(0.05, pmax(p_d_safe - 0.05, 0)) / p_d_safe
  w1 * p_l + w2 * p_l * alpha_dep
}

compute_fi <- function(SVR, p_l, p_d, alpha_dep, fresh_fact,
                       preservation_factor, fast_fraction, slow_k, k_used) {
  pl_corr <- compute_pl_eff(p_l, p_d, alpha_dep) * fresh_fact
  SVR * pl_corr * preservation_factor *
    (fast_fraction * (1 - exp(-k_used)) +
       (1 - fast_fraction) * (1 - exp(-slow_k)))
}

test_that("alpha_dep increases fi when the deep layer is active", {
  fi_low <- compute_fi(
    SVR = 0.08,
    p_l = 0.60,
    p_d = 1.00,
    alpha_dep = 0.10,
    fresh_fact = 1.00,
    preservation_factor = 0.87,
    fast_fraction = 0.30,
    slow_k = 0.05,
    k_used = 2.00
  )
  fi_high <- compute_fi(
    SVR = 0.08,
    p_l = 0.60,
    p_d = 1.00,
    alpha_dep = 0.50,
    fresh_fact = 1.00,
    preservation_factor = 0.87,
    fast_fraction = 0.30,
    slow_k = 0.05,
    k_used = 2.00
  )

  expect_gt(fi_high, fi_low)
})

test_that("alpha_dep has no effect when p_d is limited to the upper 5 cm", {
  fi_low <- compute_fi(
    SVR = 0.08,
    p_l = 0.60,
    p_d = 0.05,
    alpha_dep = 0.10,
    fresh_fact = 1.00,
    preservation_factor = 0.87,
    fast_fraction = 0.30,
    slow_k = 0.05,
    k_used = 2.00
  )
  fi_high <- compute_fi(
    SVR = 0.08,
    p_l = 0.60,
    p_d = 0.05,
    alpha_dep = 0.90,
    fresh_fact = 1.00,
    preservation_factor = 0.87,
    fast_fraction = 0.30,
    slow_k = 0.05,
    k_used = 2.00
  )

  expect_equal(fi_high, fi_low, tolerance = 1e-12)
})

test_that("fresh_fact acts multiplicatively on corrected labile fraction", {
  fi_full <- compute_fi(
    SVR = 0.08,
    p_l = 0.60,
    p_d = 1.00,
    alpha_dep = 0.25,
    fresh_fact = 1.00,
    preservation_factor = 0.87,
    fast_fraction = 0.30,
    slow_k = 0.05,
    k_used = 2.00
  )
  fi_half <- compute_fi(
    SVR = 0.08,
    p_l = 0.60,
    p_d = 1.00,
    alpha_dep = 0.25,
    fresh_fact = 0.50,
    preservation_factor = 0.87,
    fast_fraction = 0.30,
    slow_k = 0.05,
    k_used = 2.00
  )

  expect_equal(fi_half / fi_full, 0.5, tolerance = 1e-12)
})

test_that("higher k_fast multiplier increases fi with other inputs fixed", {
  fi_low_k <- compute_fi(
    SVR = 0.08,
    p_l = 0.60,
    p_d = 1.00,
    alpha_dep = 0.25,
    fresh_fact = 1.00,
    preservation_factor = 0.87,
    fast_fraction = 0.30,
    slow_k = 0.05,
    k_used = 1.00
  )
  fi_high_k <- compute_fi(
    SVR = 0.08,
    p_l = 0.60,
    p_d = 1.00,
    alpha_dep = 0.25,
    fresh_fact = 1.00,
    preservation_factor = 0.87,
    fast_fraction = 0.30,
    slow_k = 0.05,
    k_used = 3.00
  )

  expect_gt(fi_high_k, fi_low_k)
})
