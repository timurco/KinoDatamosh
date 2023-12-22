using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using UnityEngine;

[RequireComponent(typeof(Camera))]
public class Damosh : MonoBehaviour
{
    /// Size of compression macroblock.
    public int blockSize
    {
        get { return Mathf.Max(1, _blockSize); }
        set { _blockSize = value; }
    }

    [SerializeField, Range(1, 256)]
    int _blockSize = 4;

    [SerializeField, Range(0.0f, 100.0f)]
    float _denoise = 1;

    [SerializeField, Range(1.0f, 16.0f)]
    float _halfSize = 1;

    [SerializeField, Range(0, 1)]
    float _entropy = 0.5f;

    [SerializeField, Range(0.001f, 4.0f)]
    float _noiseContrast = 1;

    [SerializeField, Range(0, 2)]
    float _velocityScale = 0.8f;

    [SerializeField, Range(0, 2)]
    float _diffusion = 0.4f;

    [SerializeField] protected Material flowMaterial;
    protected RenderTexture prevFrame, flowBuffer, resultBuffer, dispBuffer, sourceBuffer;

    protected int _lastFrame;

    #region MonoBehaviour functions

    protected void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (prevFrame == null)
        {
            Setup(source.width, source.height);
            Graphics.Blit(source, prevFrame);

            ReleaseBuffer(resultBuffer);
            resultBuffer = RenderTexture.GetTemporary(Screen.width, Screen.height);
            Graphics.Blit(source, resultBuffer);
            UnityEngine.Debug.Log("First Frame");
        }

        Graphics.Blit(source, sourceBuffer);
        // ---------------------------------------------
        flowMaterial.SetFloat("_BlockSize", blockSize);
        flowMaterial.SetFloat("_Denoise", _denoise);
        flowMaterial.SetFloat("_HalfSize", _halfSize);
        // ---------------------------------------------
        flowMaterial.SetFloat("_Quality", 1 - _entropy);
        flowMaterial.SetFloat("_Contrast", _noiseContrast);
        flowMaterial.SetFloat("_Velocity", _velocityScale);
        flowMaterial.SetFloat("_Diffusion", _diffusion);

        if (Time.frameCount != _lastFrame)
        {
            flowMaterial.SetTexture("_PrevTex", prevFrame);
            Graphics.Blit(source, flowBuffer, flowMaterial, 2);
            Graphics.Blit(flowBuffer, prevFrame);

            // Update the displaceent buffer.
            var newDisp = NewDispBuffer(source.width, source.height);
            flowMaterial.SetTexture("_DispTex", flowBuffer);
            Graphics.Blit(dispBuffer, newDisp, flowMaterial, 3);
            ReleaseBuffer(dispBuffer);
            dispBuffer = newDisp;

            // Moshing!
            var newWork = RenderTexture.GetTemporary(source.width, source.height);
            flowMaterial.SetTexture("_PrevTex", resultBuffer);
            flowMaterial.SetTexture("_DispTex", dispBuffer);
            Graphics.Blit(source, newWork, flowMaterial, 4);
            ReleaseBuffer(resultBuffer);
            resultBuffer = newWork;

            _lastFrame = Time.frameCount;
        }

        Graphics.Blit(resultBuffer, destination);
    }

    RenderTexture NewDispBuffer(int width, int height)
    {
        var rt = RenderTexture.GetTemporary(
            width / _blockSize,
            height / _blockSize,
            0, RenderTextureFormat.ARGBHalf
        );
        rt.filterMode = FilterMode.Point;
        return rt;
    }

    void ReleaseBuffer(RenderTexture buffer)
    {
        if (buffer != null) RenderTexture.ReleaseTemporary(buffer);
    }

    protected void OnEnable()
    {
        flowMaterial = new Material(Shader.Find("Hidden/Kino/Damosh"));
        flowMaterial.hideFlags = HideFlags.DontSave;

        ReleaseBuffer(dispBuffer);
        dispBuffer = NewDispBuffer(Screen.width, Screen.height);
        Graphics.Blit(null, dispBuffer, flowMaterial, 0);

        
        //Graphics.Blit(null, resultBuffer, flowMaterial, 0);

        UnityEngine.Debug.Log("Enabled");
    }

    protected void Setup(int width, int height)
    {
        prevFrame = new RenderTexture(width / blockSize, height / blockSize, 0);
        prevFrame.format = RenderTextureFormat.ARGBFloat;
        prevFrame.filterMode = FilterMode.Point;
        prevFrame.Create();

        flowBuffer = new RenderTexture(width / blockSize, height / blockSize, 0);
        flowBuffer.format = RenderTextureFormat.ARGBFloat;
        flowBuffer.filterMode = FilterMode.Point;
        flowBuffer.Create();

        sourceBuffer = new RenderTexture(width, height, 0);
        sourceBuffer.format = RenderTextureFormat.ARGBFloat;
        sourceBuffer.filterMode = FilterMode.Point;
        sourceBuffer.Create();

        UnityEngine.Debug.Log("Setup");
    }

    protected void OnDisable()
    {
        if (prevFrame != null)
        {
            prevFrame.Release();
            prevFrame = null;

            flowBuffer.Release();
            flowBuffer = null;

            sourceBuffer.Release();
            sourceBuffer = null;

            ReleaseBuffer(dispBuffer);
            dispBuffer = null;

            ReleaseBuffer(resultBuffer);
            resultBuffer = null;

            DestroyImmediate(flowMaterial);
            flowMaterial = null;
        }
    }

    protected void OnGUI()
    {
        if (prevFrame == null || flowBuffer == null) return;

        const int offset = 10;
        int width = Screen.width / 5, height = Screen.height / 5;
        GUI.DrawTexture(new Rect(offset, offset, width, height), sourceBuffer);
        GUI.DrawTexture(new Rect(offset, offset + height, width, height), flowBuffer);
        GUI.DrawTexture(new Rect(offset, offset + height + height, width, height), dispBuffer);
    }


    #endregion
}
