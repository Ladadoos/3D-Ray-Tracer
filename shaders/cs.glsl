//Sources:
//-https://en.wikipedia.org/wiki/Photon_mapping
//-https://en.wikipedia.org/wiki/Bidirectional_reflectance_distribution_function
//-https://en.wikipedia.org/wiki/Jenkins_hash_function
//-https://blog.johnnovak.net/2016/10/22/the-nim-raytracer-project-part-4-calculating-box-normals/
//-https://en.wikipedia.org/wiki/Schlick%27s_approximation
//-https://graphics.stanford.edu/courses/cs348b-00/course8.pdf
//-http://viclw17.github.io/2018/08/05/raytracing-dielectric-materials/
//-http://viclw17.github.io/2018/07/20/raytracing-diffuse-materials/
//-https://karthikkaranth.me/blog/generating-random-points-in-a-sphere/
//-https://www.khronos.org/opengl/wiki/Compute_Shader
//-http://www.flipcode.com/archives/Raytracing_Topics_Techniques-Part_1_Introduction.shtml
//-http://mathworld.wolfram.com/SpherePointPicking.html

#version 430 core
layout(binding = 0, rgba32f) uniform image2D framebuffer;
layout(local_size_x = 16, local_size_y = 8) in;

const float PI = 3.1415926535897932384626433832795;
const int MAX_VALUE = 2147483647;
const float Epsilon = 0.002;
const uint MaxRayDepthCount = 4;

uniform vec3 uScreenP0; //Topleft
uniform vec3 uScreenP1; //Topright
uniform vec3 uScreenP2; //Bottomleft
uniform vec3 uCameraPosition;
uniform uint uFrameCount;

uint randSeed;

struct material{
	vec3 color;
	float roughness;
	bool isDielectric;
	float refracIndex;
};

struct light{
	vec3 position;
	vec3 color;
	float brightness;
	float radius;
};

struct ray{
	vec3 origin;
	vec3 direction;
	vec3 invDirection;
	float dist;
	uint depth;
};

struct sphere{
	vec3 position;
	float radius;
	material material;
};

struct box{
	vec3 min;
	vec3 max;
	material material;
};

struct rayhit{
	vec3 interPoint;
	float dist;
	vec3 normal;
	material material;
};

const light sceneLights[] = {
	{vec3(10, 6, -10), vec3(1, 1, 0.7), 75, 1.5},
	{vec3(-10, 6, 10), vec3(1, 1, 0.3), 75, 1.5},
	//{vec3(-15, -6, -15), vec3(0.2, 0.2, 0.9), 125, 2},
	//{vec3(15, 6, 15), vec3(0.9, 0.2, 0.8), 125, 2}
};

const sphere spheres[] = {
	{vec3(0, -3.75, 12), 1.25, material(vec3(0.9, 0.6, 0.8), 0.9, false, 0)},
	{vec3(0, -3.49, 8), 1.5, material(vec3(0.9, 0.9 ,1), 0.9, true, 1.22)},
	{vec3(0, -4.65, 10), 0.35, material(vec3(0.45, 1, 0.75), 0.5, false, 0)},
	{vec3(-3, -4.65, 9), 0.35, material(vec3(0.45, 0.5, 0.75), 0.5, false, 0)},
	{vec3(-4, -4.25, 10), 0.75, material(vec3(0.6, 0.7, 0.2), 0.9, false, 0)},
	{vec3(3, -4.35, 10), 0.65, material(vec3(0.3, 0.4, 0.5), 0.005, false, 0)},
};

const box boxes[] = {
	{vec3(-5.5, -5.5, 5), vec3(5.5, -5, 15.5), material(vec3(0.9, 0.9, 0.8), 0.9, false, 0)}, //bottom
	//{vec3(-5.1, 5, 5), vec3(5.1, 5.5, 15), material(vec3(0.3, 0.3, 0.3), 0.9, false, 0)}, //top
	{vec3(-5, -5.5, 15), vec3(5, -2, 15.5), material(vec3(0.3, 0.3, 0.3), 0.4, false, 0)}, //back
	//{vec3(-5, -5.5, 5), vec3(5, 5.5, 5.5), material(vec3(0.3, 0.3, 0.3), 0.4, false, 0)}, //front
	{vec3(-5.5, -5.5, 5.5), vec3(-5, -2, 15.5), material(vec3(0.2, 0.6, 0.2), 1, false, 0)}, //right
	//{vec3(5, -5.5, 5), vec3(5.5, 5.5, 15.5), material(vec3(0.9, 0.6, 0.3), 0.9, false, 0)}, //left

	//{vec3(-25, -15, -25), vec3(25, -14.5, 25), material(vec3(1, 0.9, 0.3), 0.8, false, 0)}, //bottom
	//{vec3(-25, 10, -25), vec3(25, 10.5, 20), material(vec3(0.1, 0.9, 0.1), 0.9, false, 0)}, //top
	//{vec3(-26.5, -15, -25), vec3(-26, 10.5, 25), material(vec3(0.3, 0.3, 0.9), 0.9, false, 0)}, //back
	//{vec3(26, -15, -25), vec3(26.5, 10.5, 25), material(vec3(0.9, 0.3, 0.3), 0.9, false, 0)}, //front
	//{vec3(-25, -15, -26.5), vec3(25, 10.5, -26), material(vec3(0.3, 0.9, 0.3), 0.9, false, 0)}, //left
	//{vec3(-25, -15, 26), vec3(25, 10.5, 26.5), material(vec3(0.3, 0.3, 0.9), 1, false, 0)}, //right

	{vec3(-5, -5, 7), vec3(-4, -4, 8), material(vec3(0.9, 0.9 ,1), 0.8, false, 1.3)}, //standalone
	{vec3(2, -5, 6), vec3(3, -3, 7), material(vec3(0.6, 0.2, 0.3), 1, false, 1.3)}, //standalone
	//{vec3(-4, -13.5, -15), vec3(4, -7, -10), material(vec3(0.9, 0.9 ,1), 0.8, false, 1.3)}, //standalone
};

uint hash() {
	uint x = randSeed;
    x += ( x << 10u );
    x ^= ( x >>  6u );
    x += ( x <<  3u );
    x ^= ( x >> 11u );
    x += ( x << 15u );
	randSeed = x;
    return x;
}

float randFloat01()
{
    return (hash() & 0xFFFFFF) / 16777216.0f;
}

bool rayIntersectsSphere(vec3 pos, float radius, ray r, out float dist){
	vec3 c = pos - r.origin;
	float t = dot(c, r.direction);
	vec3 q = c - t * r.direction;
	float p = dot(q,q);
	float r2 = radius * radius;
	if(p > r2){ return false; }
	t -= sqrt(r2 - p);
	if(t > 0 && t < r.dist){ dist = t; return true; }	
	return false;
}

bool rayIntersectsBox(const box b, ray r, out float dist){
	vec3 vMin = (b.min - r.origin) * r.invDirection;
	vec3 vMax = (b.max - r.origin) * r.invDirection;
	float tmin = max(max(min(vMin.x, vMax.x), min(vMin.y, vMax.y)), min(vMin.z, vMax.z));
	float tmax = min(min(max(vMin.x, vMax.x), max(vMin.y, vMax.y)), max(vMin.z, vMax.z));

	// if tmax < 0, intersection, but the whole AABB is behind us. if tmin > tmax, no intersction
	if (tmax < 0 || tmin > tmax || tmin> r.dist){ return false; }
	dist = tmin;
	return true;
}

const float bias = 1.00005;
vec3 getNormalBoxAtIntersection(const box b, vec3 interPoint){
	vec3 c = (b.min + b.max) * 0.5;
	vec3 p = interPoint - c;
	vec3 d = (b.min - b.max) * 0.5;
	return normalize(vec3(int(p.x / abs(d.x) * bias), int(p.y / abs(d.y) * bias), int(p.z / abs(d.z) * bias)));
}

bool intersectSceneShadowRay(ray r){
	float t;
	for(int i = 0; i < spheres.length(); i++){
		if(rayIntersectsSphere(spheres[i].position, spheres[i].radius, r, t)){ return true; }
	}
	for(int i = 0; i < boxes.length(); i++){
		if(rayIntersectsBox(boxes[i], r, t)){ return true; }
	}
	return false;
}

int intersectScenePrimaryRay(ray r, out rayhit rHit){
	int hit = 0;
	float dist = MAX_VALUE;

	for(int i = 0; i < boxes.length(); i++){
		box b = boxes[i];
		if(rayIntersectsBox(b, r, dist)){			
			hit = 1;
			r.dist = dist;
			rHit.dist = dist;
			rHit.interPoint = r.origin + r.direction * rHit.dist;			
			rHit.normal = getNormalBoxAtIntersection(b, rHit.interPoint);
			rHit.material = b.material;		
		}
	}

	for(int i = 0; i < spheres.length(); i++){
		sphere sphr = spheres[i];
		if(rayIntersectsSphere(sphr.position, sphr.radius, r, dist)){			
			hit = 1;
			r.dist = dist;
			rHit.dist = dist;
			rHit.interPoint = r.origin + r.direction * rHit.dist;
			rHit.normal = (rHit.interPoint - sphr.position) / sphr.radius;
			rHit.material = sphr.material;
		}
	}

	for(int i = 0; i < sceneLights.length(); i++){
		light lit = sceneLights[i];
		if(rayIntersectsSphere(lit.position, lit.radius, r, dist)){		
			hit = 2;
			r.dist = dist;	
			rHit.dist = dist;
			rHit.interPoint = r.origin + r.direction * rHit.dist;
			rHit.normal = (rHit.interPoint - lit.position) / lit.radius;
			rHit.material.color = lit.color;
		}
	}

	return hit;
}

vec3 randPointInSphere(vec3 pos, float r){
	float theta = PI * randFloat01() * 2;
	float phi = acos(randFloat01() * 2 - 1);
	float sinPhi = sin(phi);
	float x = pos.x + r * sinPhi * cos(theta);
	float y = pos.y + r * sinPhi * sin(theta);
	float z = pos.z + r * cos(phi);
	return vec3(x, y, z);
}

bool isVisible(vec3 origin, vec3 toLightDir, float toLightDist, vec3 surfaceNormal){
	ray shadowRay = ray(origin, toLightDir, 1 / toLightDir, toLightDist, 0);
	return !intersectSceneShadowRay(shadowRay);
}

vec3 directIllumination(vec3 interPoint, vec3 surfaceNormal){
	vec3 finalColor = vec3(1);

	for(int i = 0; i < sceneLights.length(); i++){
		light lit = sceneLights[i];
		vec3 toLightVector = randPointInSphere(lit.position, lit.radius) - interPoint;
		float toLightDist = length(toLightVector);
		toLightVector *= (1 / toLightDist); //normalize
		vec3 origin = interPoint + toLightVector * Epsilon;
		toLightDist -= 2 * Epsilon; //prevent shadow acne
		float surfaceDotDir = dot(surfaceNormal, toLightVector);
		
		if(surfaceDotDir < 0){ continue; } //light is behind surface, continue		
		if(isVisible(origin, toLightVector, toLightDist, surfaceNormal)){
			float attenuation = 1 / (toLightDist * toLightDist);
			finalColor += lit.color * surfaceDotDir * attenuation * lit.brightness;
		}		
	}

	return finalColor;
}

float uniformRandBetween(float a, float b) {
  return a + randFloat01() * (b - a);
}

vec3 uniformRandInHemisphere(vec3 dir, float spread) {
  vec3 different; //orthogonal basis with 3rd vector being dir
  if(abs(dir.x) < 0.5f){
	different = vec3(1.0f, 0.0f, 0.0f);
  }else{
	different = vec3(0.0f, 1.0f, 0.0f);
  }
  
  vec3 b1 = normalize(cross(dir, different));
  vec3 b2 = cross(b1, dir);
 
  //pick random point around (0,0,1)
  float z = uniformRandBetween(cos(spread * PI), 1);
  float r = sqrt(1.0f - z * z);
  float theta = uniformRandBetween(-PI, +PI);
  float x = r * cos(theta);
  float y = r * sin(theta);
  return x * b1 + y * b2 + z * dir;
}

float schlick(float cosAngle, float refleCoe)
{
    float r0 = (1.0 - refleCoe) / (1.0 + refleCoe);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow((1.0 - cosAngle), 5);
}

vec4 trace(ray initRay){
	rayhit rHit;
	ray r = initRay;
	vec3 color = vec3(1);
	int rayDepth = 0;
	while(rayDepth < MaxRayDepthCount){	
		rayDepth++;
		int res = intersectScenePrimaryRay(r, rHit);
		if(res == 0){
			float y = 0.75 * (r.direction.y + 1);
			float minY = 1.0 - y;
			color *= (vec3(minY) + y * vec3(0.4, 0.8, 1.0));
			break;
		}else if(res == 2){
			color *= rHit.material.color;
			break;
		}

		color *= rHit.material.color;
		if(rHit.material.isDielectric){
			float snellRatio, cosine;
			vec3 normal;
			float dirDotNormal = dot(r.direction, rHit.normal);
			if(dirDotNormal > 0){ //hit from inside
				normal = -rHit.normal;
				snellRatio = rHit.material.refracIndex;
				cosine = dirDotNormal;
			}else{
				normal = rHit.normal;
				snellRatio = 1 / rHit.material.refracIndex;
				cosine = -dirDotNormal;
			}
			
			float reflectProb = 1;
			if(1 - snellRatio * snellRatio * (1 - dirDotNormal * dirDotNormal) > 0){
				reflectProb = schlick(cosine, rHit.material.refracIndex);
			}

			if(randFloat01() < reflectProb){
				r.direction = reflect(r.direction, rHit.normal);
			}else{
				r.direction = refract(r.direction, rHit.normal, snellRatio);
			}
			r.invDirection = 1 / r.direction;
			r.origin = rHit.interPoint + r.direction * Epsilon;
			r.dist = MAX_VALUE;
		}else{
			if(rHit.material.roughness > 0){ //if not pure specular
				color *= directIllumination(rHit.interPoint, rHit.normal);
			}

			if(randFloat01() < 0.1){
				vec3 ref =reflect(r.direction, rHit.normal);
				r.direction = normalize(ref + rHit.material.roughness * uniformRandInHemisphere(ref, 0.1));			
			}else{
				r.direction = normalize(reflect(r.direction, rHit.normal) + rHit.material.roughness * uniformRandInHemisphere(rHit.normal, 1));
			}
			r.invDirection = 1 / r.direction;
			r.origin = rHit.interPoint + r.direction * Epsilon;
			r.dist = MAX_VALUE;
		}
	}

	return vec4(color, 1);
}

void main() {
	ivec2 pixelCoords = ivec2(gl_GlobalInvocationID.xy);
	ivec2 screenSize = imageSize(framebuffer);
	if (pixelCoords.x >= screenSize.x || pixelCoords.y >= screenSize.y) { return; }

	randSeed = gl_GlobalInvocationID.x * 1973 + gl_GlobalInvocationID.y * 9277 + uFrameCount * 2699 | 1;

	vec4 pixelColor = vec4(0, 0, 0, 1);
	float u = (screenSize.x - pixelCoords.x + randFloat01()) / screenSize.x;
	float v = (screenSize.y - pixelCoords.y + randFloat01()) / screenSize.y;
	vec3 screenPoint = uScreenP0 + u * (uScreenP1 - uScreenP0) + v * (uScreenP2 - uScreenP0);
	vec3 rayDirection = normalize(screenPoint - uCameraPosition);
	ray primaryRay = ray(uCameraPosition, rayDirection, 1 / rayDirection, MAX_VALUE, 0);
	pixelColor = trace(primaryRay);

	vec4 oldPixelColor = imageLoad(framebuffer, pixelCoords);
	vec4 newPixelColor = (oldPixelColor * (uFrameCount - 1) + pixelColor) / uFrameCount;
	imageStore(framebuffer, pixelCoords, newPixelColor);
}