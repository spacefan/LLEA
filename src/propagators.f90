!
! Copyright (c) 2016 Helge Eichhorn
!
! This Source Code Form is subject to the terms of the Mozilla Public
! License, v. 2.0. If a copy of the MPL was not distributed with this
! file, You can obtain one at http://mozilla.org/MPL/2.0/.
!
! This file incorporates work covered by the following copyright and
! permission notice:
!
!   The MIT License (MIT)
!
!   Copyright (c) 2012-2015 Juan Luis Cano Rodríguez
!
!   Permission is hereby granted, free of charge, to any person obtaining a copy
!   of this software and associated documentation files (the "Software"), to deal
!   in the Software without restriction, including without limitation the rights
!   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
!   copies of the Software, and to permit persons to whom the Software is
!   furnished to do so, subject to the following conditions:
!
!   The above copyright notice and this permission notice shall be included in all
!   copies or substantial portions of the Software.
!
!   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
!   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
!   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
!   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
!   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
!   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
!   SOFTWARE.
!
module propagators

use types, only: dp
use epochs, only: epochdelta, seconds, operator (+)
use exceptions
use math, only: eps, isapprox, norm, pih, cross, cot, linspace
use states, only: state
use trajectories, only: trajectory

implicit none

type kepler
    integer :: iterations = 50
    integer :: points = 100
    real(dp) :: rtol = sqrt(eps)
end type kepler

interface kepler
    module procedure kepler_init
end interface kepler

private

public :: kepler, solve_kepler, getstate, gettrajectory

interface getstate
    module procedure getstate_kepler_dp
    module procedure getstate_kepler_epochdelta
end interface getstate

interface gettrajectory
    module procedure gettrajectory_kepler_epochdelta
end interface gettrajectory

contains

function gettrajectory_kepler_epochdelta(s0, epd, p, err) result(tra)
    type(state), intent(in) :: s0
    type(epochdelta), intent(in) :: epd
    type(kepler), intent(in) :: p
    type(exception), intent(inout), optional :: err
    type(trajectory) :: tra

    integer :: i
    real(dp), dimension(p%points) :: times
    real(dp) :: dt
    type(exception) :: err_

    dt = seconds(epd)
    times = linspace(0._dp, dt, p%points)
    tra%initial_state = s0
    tra%fields = ["x ", "y ", "z ", "vx", "vy", "vz"]
    allocate(tra%vectors(6, p%points))
    do i = 1, p%points
        tra%vectors(:, i) = solve_kepler(s0%center%mu, s0%rv, times(i), p%iterations, &
            p%rtol, err_)
        if (iserror(err_)) then
            call catch(err_, "gettrajectory_kepler_epochdelta", __FILE__, __LINE__)
            if (present(err)) then
                err = err_
                return
            else
                call raise(err_)
            end if
        end if
    end do
    tra%final_state = state(s0%ep + epd, tra%vectors(:, p%points), s0%frame, s0%center)
endfunction gettrajectory_kepler_epochdelta

function getstate_kepler_dp(s0, dt, p, err) result(s1)
    type(state), intent(in) :: s0
    real(dp), intent(in) :: dt
    type(kepler), intent(in) :: p
    type(exception), intent(inout), optional :: err

    type(state) :: s1
    type(exception) :: err_
    type(epochdelta) :: epd

    epd = epochdelta(seconds=dt)
    s1 = getstate_kepler_epochdelta(s0, epd, p, err_)
    if (iserror(err_)) then
        call catch(err_, "getstate_kepler_dp", __FILE__, __LINE__)
        if (present(err)) then
            err = err_
            return
        else
            call raise(err_)
        end if
    end if
end function getstate_kepler_dp

function getstate_kepler_epochdelta(s0, epd, p, err) result(s1)
    type(state), intent(in) :: s0
    type(epochdelta), intent(in) :: epd
    type(kepler), intent(in) :: p
    type(exception), intent(inout), optional :: err

    type(state) :: s1
    type(exception) :: err_
    real(dp), dimension(6) :: rv1

    rv1 = solve_kepler(s0%center%mu, s0%rv, seconds(epd), p%iterations, p%rtol, err_)
    if (iserror(err_)) then
        call catch(err_, "getstate_kepler_epochdelta", __FILE__, __LINE__)
        if (present(err)) then
            err = err_
            return
        else
            call raise(err_)
        end if
    end if
    s1 = state(s0%ep + epd, rv1, s0%frame, s0%center)
end function getstate_kepler_epochdelta

function kepler_init(iterations, points, rtol) result(kep)
    integer, intent(in), optional :: iterations
    integer, intent(in), optional :: points
    real(dp), intent(in), optional :: rtol

    type(kepler) :: kep

    if (present(iterations)) kep%iterations = iterations
    if (present(points)) kep%points = points
    if (present(rtol)) kep%rtol = rtol
end function kepler_init

function solve_kepler(mu, rv, dt, iterations, rtol, err) result(rv1)
    real(dp), intent(in) :: mu
    real(dp), dimension(:), intent(in) :: rv
    real(dp), intent(in) :: dt
    integer, intent(in), optional :: iterations
    real(dp), intent(in), optional :: rtol
    type(exception), intent(inout), optional :: err

    real(dp), dimension(6) :: rv1
    type(exception) :: err_
    integer :: iterations_
    real(dp) :: rtol_
    real(dp) :: rm
    real(dp) :: rdotv
    real(dp) :: alpha
    real(dp) :: xi1
    real(dp) :: xi2
    real(dp), dimension(3) :: h
    real(dp) :: hm
    real(dp) :: p
    real(dp) :: s
    real(dp) :: w
    real(dp) :: a
    integer :: counter
    logical :: converged
    real(dp) :: xi
    real(dp) :: c2
    real(dp) :: c3
    real(dp) :: r
    real(dp) :: psi
    real(dp) :: deltat
    real(dp) :: f
    real(dp) :: g
    real(dp) :: fdot
    real(dp) :: gdot

    iterations_ = 50
    if (present(iterations)) iterations_ = iterations
    rtol_ = sqrt(eps)
    if (present(rtol)) rtol_ = rtol

    if (abs(dt) < rtol_) then
        rv1 = rv
        return
    end if

    rm = norm(rv(1:3))
    rdotv = dot_product(rv(1:3), rv(4:6))
    alpha = -dot_product(rv(4:6), rv(4:6)) / mu + 2._dp / rm

    ! Elliptic orbit
    if (alpha > rtol_) then
        if (isapprox(alpha, 1._dp)) then
            xi1 = sqrt(mu) * dt * alpha * 0.97_dp
        else
            xi1 = sqrt(mu) * dt * alpha
        end if
    ! Parabolic orbit
    else if (abs(alpha) < rtol_) then
        h = cross(rv(1:3), rv(4:6))
        hm = norm(h)
        p = hm * hm / mu
        s = 0.5_dp * (pih - atan(3._dp * sqrt(mu / p**3) * dt))
        w = atan(tan(s)**(1._dp/3._dp))
        xi1 = sqrt(p) * (2._dp * cot(2._dp * w))
        alpha = 0._dp
    ! Hyperbolic orbit
    else
        a = 1._dp / alpha
        xi1 = sign(1._dp, dt) * sqrt(-a) * log(-2._dp * mu * dt &
            / (a * (rdotv + sign(1._dp, dt) * sqrt(-mu * alpha) * (1._dp - rm * alpha))))
    end if

    counter = 0
    converged = .false.
    xi = 0._dp
    xi2 = 0._dp
    c2 = 0._dp
    c3 = 0._dp
    r = 0._dp
    psi = 0._dp

    do while (counter < iterations_)
        counter = counter + 1
        xi = xi1
        xi2 = xi * xi
        psi = xi2 * alpha
        c2 = stumpffc2(psi)
        c3 = stumpffc3(psi)
        r = xi2 * c2 + rdotv / sqrt(mu) * xi * (1 - psi * c3) + rm * (1 - psi * c2)
        deltat = xi2 * xi * c3 + rdotv / sqrt(mu) * xi2 * c2 + rm * xi * (1 - psi * c3)
        xi1 = xi + (dt * sqrt(mu) - deltat) / r
        if (abs(xi - xi1) < rtol_) then
            converged = .true.
            exit
        end if
    end do

    if (.not.converged) then
        err_ = error("Kepler solver did not converge.", "solve_kepler", __FILE__, __LINE__)
        if (present(err)) then
            err = err_
            return
        else
            call raise(err_)
        end if
    end if

    f = 1._dp - xi2 / rm * c2
    g = dt - xi2 * xi / sqrt(mu) * c3
    fdot = sqrt(mu) / (r * rm) * xi * (psi * c3 - 1)
    gdot = 1 - xi2 / r * c2
    rv1 = [f * rv(1:3) + g * rv(4:6), fdot * rv(1:3) + gdot * rv(4:6)]
end function solve_kepler

function stumpffc2(psi) result(res)
    real(dp), intent(in) :: psi
    real(dp) :: res

    real(dp) :: eps
    real(dp) :: delta
    integer :: k

    eps = 1._dp
    if (psi > eps) then
        res = (1._dp - cos(sqrt(psi))) / psi
    else if (psi < -eps) then
        res = (cosh(sqrt(-psi)) - 1._dp) / (-psi)
    else
        res = 1._dp / 2._dp
        delta = (-psi) / gamma(2._dp + 2._dp + 1._dp)
        k = 1
        do while (.not.isapprox(res + delta, res))
            res = res + delta
            k = k + 1
            delta = (-psi)**k / gamma(2._dp*k + 2._dp + 1._dp)
        end do
    end if
end function stumpffc2

function stumpffc3(psi) result(res)
    real(dp), intent(in) :: psi
    real(dp) :: res

    real(dp) :: eps
    real(dp) :: delta
    integer :: k

    eps = 1._dp
    if (psi > eps) then
        res = (sqrt(psi) - sin(sqrt(psi))) / (psi * sqrt(psi))
    else if (psi < -eps) then
        res = (sinh(sqrt(-psi)) - sqrt(-psi)) / (-psi * sqrt(-psi))
    else
        res = 1._dp / 6._dp
        delta = (-psi) / gamma(2._dp + 3._dp + 1._dp)
        k = 1
        do while (.not.isapprox(res + delta, res))
            res = res + delta
            k = k + 1
            delta = (-psi)**k / gamma(2._dp*k + 3._dp + 1._dp)
        end do
    end if
end function stumpffc3

end module propagators