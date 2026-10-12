class_name Atmosphere
extends RefCounted
## CPU twin of the scattering model in shaders/sky.gdshader (v0.17).
##
## DayNight asks it what the clear sky looks like straight up and along the
## horizon: those two colours light the clouds from below, tint the water, and
## the table below sets the exposure that keeps a physically based sky readable
## from noon to dusk. Keep the constants in step with the shader.

const RG := 6360.0
const RT := 6420.0
const H0 := 0.3
const BR := Vector3(5.802e-3, 13.558e-3, 33.1e-3)
const BMS := 3.996e-3
const BME := 4.440e-3
const BO := Vector3(0.975e-3, 2.8215e-3, 0.1275e-3)
const HR := 8.0
const HM := 1.2

## Cosine-weighted luminance of the clear upper hemisphere (turbidity 1.4) by
## sun elevation in degrees, measured with tools/sky_table.gd (this model, 12 steps).
const LUM_EL := [-5.0, -4.0, -3.0, -2.0, -1.5, -1.0, -0.5, 0.0, 1.0, 2.0, 3.0, 4.0, 6.0,
	8.0, 10.0, 13.0, 16.0, 20.0, 25.0, 30.0, 40.0, 50.0, 60.0, 75.0, 90.0]
const LUM := [5.906e-05, 0.0001819, 0.0004991, 0.0008804, 0.001096, 0.001337, 0.001624,
	0.002272, 0.003687, 0.004716, 0.005663, 0.006524, 0.007954, 0.009066, 0.009945, 0.01096,
	0.01172, 0.01248, 0.01317, 0.01368, 0.0144, 0.01488, 0.01522, 0.01553, 0.01563]

static func chapman(x: float, cosc: float) -> float:
	var c := sqrt(1.5707963 * x)
	var pos := c / ((c - 1.0) * absf(cosc) + 1.0)
	if cosc >= 0.0:
		return pos
	var x0 := x * sqrt(maxf(1.0 - cosc * cosc, 0.0))
	var c0 := sqrt(1.5707963 * x0)
	return 2.0 * c0 * exp(minf(x - x0, 60.0)) - pos

## Optical depth (Rayleigh, Mie, ozone) from altitude h km to space along a
## direction whose zenith cosine is cosc.
static func od_light(h: float, cosc: float) -> Vector3:
	var r := RG + h
	var odr := HR * exp(-h / HR) * chapman(r / HR, cosc)
	var odm := HM * exp(-h / HM) * chapman(r / HM, cosc)
	var k := r / (RG + 25.0)
	var cs := sqrt(maxf(1.0 - (1.0 - cosc * cosc) * k * k, 0.0))
	var am := 1.0 / maxf(cs, 0.035)
	if cosc < 0.0:
		am *= 2.0
	var odo := 15.0 * am * clampf(1.0 - maxf(h - 25.0, 0.0) / 15.0, 0.0, 1.0)
	return Vector3(odr, odm, odo)

static func trans(od: Vector3, turb: float) -> Vector3:
	var t := BR * od.x + Vector3.ONE * (BME * turb * od.y) + BO * od.z
	return Vector3(exp(-t.x), exp(-t.y), exp(-t.z))

static func _phase_r(mu: float) -> float:
	return 0.0596831 * (1.0 + mu * mu)

static func _phase_m(mu: float, g: float) -> float:
	var g2 := g * g
	return 0.1193662 * (1.0 - g2) * (1.0 + mu * mu) / ((2.0 + g2) * pow(maxf(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5))

## Clear-sky radiance towards d for unit sun irradiance (multiply by the
## exposure to get what the shader draws).
static func inscatter(d: Vector3, sd: Vector3, turb: float, steps: int = 10) -> Vector3:
	var dd := Vector3(d.x, maxf(d.y, 0.0), d.z).normalized()
	var o := RG + H0
	var b := o * dd.y
	var c := o * o - RT * RT
	var tmax := minf(-b + sqrt(b * b - c), 100.0)
	var od := Vector3.ZERO
	var inr := Vector3.ZERO
	var inm := Vector3.ZERO
	var ms := Vector3.ZERO
	var fs := float(steps)
	for i in steps:
		var f0 := float(i) / fs
		var f1 := float(i + 1) / fs
		f0 *= f0
		f1 *= f1
		var tm := 0.5 * (f0 + f1) * tmax
		var dt := (f1 - f0) * tmax
		var p := Vector3(dd.x * tm, o + dd.y * tm, dd.z * tm)
		var r := p.length()
		var h := maxf(r - RG, 0.0)
		var dens := Vector3(exp(-h / HR), exp(-h / HM), clampf(1.0 - absf(h - 25.0) / 15.0, 0.0, 1.0))
		od += dens * (dt * 0.5)
		var tv := trans(od, turb)
		var t := tv * trans(od_light(h, p.dot(sd) / r), turb)
		inr += t * (dens.x * dt)
		inm += t * (dens.y * dt)
		ms += tv * (BR * dens.x + Vector3.ONE * (BMS * turb * dens.y)) * dt
		od += dens * (dt * 0.5)
	var mu := d.dot(sd)
	var tms := trans(od_light(4.0, clampf(sd.y + 0.06, -1.0, 1.0)), turb)
	return BR * inr * _phase_r(mu) + inm * (BMS * turb * _phase_m(mu, 0.76)) + ms * tms * (0.2 / (4.0 * PI))

## Interpolated (log-linear) LUM table.
static func hemisphere_lum(elev_deg: float) -> float:
	var e := clampf(elev_deg, LUM_EL[0], LUM_EL[LUM_EL.size() - 1])
	for i in LUM_EL.size() - 1:
		var e0: float = LUM_EL[i]
		var e1: float = LUM_EL[i + 1]
		if e <= e1:
			var t := (e - e0) / maxf(e1 - e0, 1e-4)
			return exp(lerpf(log(float(LUM[i])), log(float(LUM[i + 1])), t))
	return float(LUM[LUM.size() - 1])
