using System;
using System.Drawing;
using System.IO;
using OpenTK;
using OpenTK.Graphics.OpenGL;
using OpenTK.Input;

namespace RayTracer
{
    public class OpenTKApp : GameWindow
    {
        private bool terminated = false;

        private int screenTextureId, screenQuadVaoId, computeProgramId, quadProgramId;

        private uint frameCount = 1;
        private int attributeFrameCountId;

        private const int screenWidth = 1024; //MUST BE POWER OF TWO
        private const int screenHeight = 1024; //MUST BE POWER OF TWO

        private int[] workGroupInvocations = new int[1];
        private int[] workGroupCountXYZ = new int[3];
        private int[] workGroupCountX = new int[1];
        private int[] workGroupCountY = new int[1];
        private int[] workGroupCountZ = new int[1];
        private int[] workGroupSizeX = new int[1];
        private int[] workGroupSizeY = new int[1];
        private int[] workGroupSizeZ = new int[1];

        private const int groupNumberX = screenWidth / 16;
        private const int groupNumberY = screenHeight / 8;

        private const float screenDistance = 1;
        private Vector3 camPosition, camForward, camRight, camUp;
        private Vector3 screenP0, screenP1, screenP2;
        private int attributeScreenP0, attributeScreenP1, attributeScreenP2, attributeCameraPos;
        private float yaw, pitch;
        private Vector2 prevMousePos;
        private const float camSpeed = 0.5F;
        private const float camSensi = 0.1F;

        private bool updateWorldState = false;

        protected override void OnLoad(EventArgs e)
        {
            ClientSize = new Size(screenWidth, screenHeight);

            GL.Hint(HintTarget.PerspectiveCorrectionHint, HintMode.Nicest);
            VSync = VSyncMode.Off;

            Console.WriteLine("OpenGL version: " + GL.GetString(StringName.Version));

            GL.GetInteger((GetIndexedPName)All.MaxComputeWorkGroupCount, 0, workGroupCountX);
            GL.GetInteger((GetIndexedPName)All.MaxComputeWorkGroupCount, 1, workGroupCountY);
            GL.GetInteger((GetIndexedPName)All.MaxComputeWorkGroupCount, 2, workGroupCountZ);
            Console.WriteLine("Global total work group count -> x:" + workGroupCountX[0] + " y:" + workGroupCountY[0] + " z:" + workGroupCountZ[0]);

            GL.GetInteger((GetIndexedPName)All.MaxComputeWorkGroupSize, 0, workGroupSizeX);
            GL.GetInteger((GetIndexedPName)All.MaxComputeWorkGroupSize, 1, workGroupSizeY);
            GL.GetInteger((GetIndexedPName)All.MaxComputeWorkGroupSize, 2, workGroupSizeZ);
            Console.WriteLine("Global total work group size -> x:" + workGroupSizeX[0] + " y:" + workGroupSizeY[0] + " z:" + workGroupSizeZ[0]);

            GL.GetInteger((GetPName)All.MaxComputeWorkGroupInvocations, workGroupInvocations);
            Console.WriteLine("Global total work group invocations -> " + workGroupInvocations[0]);

            Console.WriteLine("Num groups x: " + (float)screenWidth / workGroupSizeX[0] + " Num groups y: " + (float)screenHeight / workGroupSizeY[0]);

            screenTextureId = CreateScreenTexture();
            screenQuadVaoId = CreateScreenVAO();
            computeProgramId = CreateComputeProgram();
            InitializeComputeProgram();
            quadProgramId = CreateQuadProgram();
            InitializeQuadProgram();
        }

        private void InitializeComputeProgram()
        {
            GL.UseProgram(computeProgramId);

            attributeFrameCountId = GL.GetUniformLocation(computeProgramId, "uFrameCount");
            GL.Uniform1(attributeFrameCountId, frameCount);

            camForward = new Vector3(1, 0, 0);
            UpdateScreenSpace();
            Vector3 screenCenter = camPosition + camForward * screenDistance;

            attributeScreenP0 = GL.GetUniformLocation(computeProgramId, "uScreenP0");
            GL.Uniform3(attributeScreenP0, screenCenter + screenP0);
            attributeScreenP1 = GL.GetUniformLocation(computeProgramId, "uScreenP1");
            GL.Uniform3(attributeScreenP1, screenCenter + screenP1);
            attributeScreenP2 = GL.GetUniformLocation(computeProgramId, "uScreenP2");
            GL.Uniform3(attributeScreenP2, screenCenter + screenP2);

            attributeCameraPos = GL.GetUniformLocation(computeProgramId, "uCameraPosition");
            GL.Uniform3(attributeCameraPos, camPosition);

            GL.UseProgram(0);
        }

        private void InitializeQuadProgram()
        {
            GL.UseProgram(quadProgramId);
            GL.Uniform1(GL.GetUniformLocation(quadProgramId, "screenTexture"), 0);
            GL.UseProgram(0);
        }

        private int CreateQuadProgram()
        {
            int quadProgram = GL.CreateProgram();
            int fragmentShader = CreateShader(ShaderType.FragmentShader, "../../shaders/fs.glsl");
            int vertexShader = CreateShader(ShaderType.VertexShader, "../../shaders/vs.glsl");

            GL.AttachShader(quadProgram, vertexShader);
            GL.AttachShader(quadProgram, fragmentShader);
            GL.BindAttribLocation(quadProgram, 0, "vertex");
            GL.BindFragDataLocation(quadProgram, 0, "outColor");
            GL.LinkProgram(quadProgram);

            return quadProgram;
        }

        private int CreateShader(ShaderType type, string fileDirectory)
        {
            int shader = GL.CreateShader(type);
            using (StreamReader sr = new StreamReader(fileDirectory))
            {
                GL.ShaderSource(shader, sr.ReadToEnd());
            }
            GL.CompileShader(shader);
            Console.WriteLine("Shader[" + type.ToString() + "] log:" + GL.GetShaderInfoLog(shader));
            return shader;
        }

        private int CreateComputeProgram()
        {
            int program = GL.CreateProgram();
            int computeShader = CreateShader(ShaderType.ComputeShader, "../../shaders/cs.glsl");
            GL.AttachShader(program, computeShader);
            GL.LinkProgram(program);
            return program;
        }

        private int CreateScreenVAO()
        {
            float[] data = new float[8]{
                -1.0f, -1.0f,
                -1.0f, 1.0f,
                1.0f, 1.0f,
                1.0f, -1.0f
            };

            int vao = GL.GenVertexArray();
            int vbo = GL.GenBuffer();
            GL.BindVertexArray(vao);
            GL.BindBuffer(BufferTarget.ArrayBuffer, vbo);
            GL.BufferData(BufferTarget.ArrayBuffer, sizeof(float) * 8, data, BufferUsageHint.StaticDraw);
            GL.EnableVertexAttribArray(0);
            GL.VertexAttribPointer(0, 2, VertexAttribPointerType.Float, false, 0, 0);
            GL.BindVertexArray(0);
            return vao;
        }

        private int CreateScreenTexture()
        {
            int textureHandle = GL.GenTexture();
            GL.BindTexture(TextureTarget.Texture2D, textureHandle);
            GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMagFilter, (int)TextureMagFilter.Nearest);
            GL.TexParameter(TextureTarget.Texture2D, TextureParameterName.TextureMinFilter, (int)TextureMinFilter.Nearest);
            GL.TexImage2D(TextureTarget.Texture2D, 0, PixelInternalFormat.Rgba32f, screenWidth, screenHeight, 0, PixelFormat.Rgba, PixelType.Float, (IntPtr)null);
            GL.BindImageTexture(0, textureHandle, 0, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.Rgba32f);
            return textureHandle;
        }

        protected override void OnUnload(EventArgs e)
        {
            GL.DeleteTexture(screenTextureId);
            Environment.Exit(0);
        }

        protected override void OnResize(EventArgs e)
        {
            GL.Viewport(0, 0, Width, Height);
            GL.MatrixMode(MatrixMode.Projection);
            GL.LoadIdentity();
            GL.Ortho(-1.0, 1.0, -1.0, 1.0, 0.0, 4.0);
        }

        protected override void OnUpdateFrame(FrameEventArgs e)
        {
            var kb = Keyboard.GetState();
            if (kb[Key.Escape]) terminated = true;

            bool update = false;
            Vector2 currMousePos = new Vector2(Mouse.GetState().X, Mouse.GetState().Y);

            if (kb[Key.W])
            {
                camPosition += camForward * camSpeed;
                update = true;
            } else if (kb[Key.S])
            {
                camPosition -= camForward * camSpeed;
                update = true;
            }
            if (kb[Key.A])
            {
                camPosition += camRight * camSpeed;
                update = true;
            } else if (kb[Key.D])
            {
                camPosition -= camRight * camSpeed;
                update = true;
            }

            if (Focused && prevMousePos != currMousePos)
            {
                float deltaX = (prevMousePos.X - Mouse.GetState().X) * camSensi;
                float deltaY = (prevMousePos.Y - Mouse.GetState().Y) * camSensi;
                yaw -= deltaX;
                pitch += deltaY;
                if (pitch > 89.0f) { pitch = 89.0f; }
                if (pitch < -89.0f) { pitch = -89.0f; }
                double pitchRad = pitch * Math.PI / 180;
                double yawRad = yaw * Math.PI / 180;
                double cosPitch = Math.Cos(pitchRad);
                camForward.X = (float)(cosPitch * Math.Cos(yawRad));
                camForward.Y = (float)(Math.Sin(pitchRad));
                camForward.Z = (float)(cosPitch * Math.Sin(yawRad));
                camForward.Normalize();

                prevMousePos = currMousePos;
                Mouse.SetPosition(Bounds.Left + Bounds.Width / 2, Bounds.Top + Bounds.Height / 2);
                update = true;
            }

            if (update)
            {
                UpdateScreenSpace();
                frameCount = 0;
                updateWorldState = true;
            }
        }

        protected void UpdateScreenSpace()
        {
            camRight = Vector3.Normalize(Vector3.Cross(Vector3.UnitY, camForward));
            camUp = Vector3.Cross(camForward, camRight);

            Vector3 screenCenter = camPosition + camForward * screenDistance;
            screenP0 = screenCenter - camRight + camUp;
            screenP1 = screenCenter + camRight + camUp;
            screenP2 = screenCenter - camRight - camUp;
        }

        double averageFps;
        protected override void OnRenderFrame(FrameEventArgs e)
        {
            if (terminated)
            {
                Exit();
                return;
            }

            averageFps = (averageFps * (frameCount) + (1.0F / e.Time)) / (frameCount + 1);
            Title = "Average FPS: " + averageFps;

            GL.UseProgram(computeProgramId);
            GL.BindImageTexture(0, screenTextureId, 0, false, 0, TextureAccess.WriteOnly, SizedInternalFormat.Rgba32f);
            frameCount++;
            GL.Uniform1(attributeFrameCountId, frameCount);
            if (updateWorldState)
            {
                GL.Uniform3(attributeCameraPos, camPosition);
                GL.Uniform3(attributeScreenP0, screenP0);
                GL.Uniform3(attributeScreenP1, screenP1);
                GL.Uniform3(attributeScreenP2, screenP2);
                updateWorldState = false;
            }
            

            GL.DispatchCompute(groupNumberX, groupNumberY, 1);

            GL.BindImageTexture(0, 0, 0, false, 0, TextureAccess.ReadWrite, SizedInternalFormat.Rgba32f);
            GL.MemoryBarrier(MemoryBarrierFlags.ShaderImageAccessBarrierBit);
            GL.UseProgram(0);

            GL.UseProgram(quadProgramId);
            GL.BindVertexArray(screenQuadVaoId);
            GL.BindTexture(TextureTarget.Texture2D, screenTextureId);
            GL.DrawArrays(PrimitiveType.Quads, 0, 4);
            GL.BindTexture(TextureTarget.Texture2D, 0);
            GL.BindVertexArray(0);
            GL.UseProgram(0);

            SwapBuffers();
        }

        public static void Main(string[] args)
        {
            using (OpenTKApp app = new OpenTKApp()) { app.Run(30.0, 0.0); }
        }
    }
}