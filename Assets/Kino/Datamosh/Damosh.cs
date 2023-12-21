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
    [Tooltip("Size of compression macroblock.")]
    int _blockSize = 4;

    [SerializeField] protected Material flowMaterial;
    protected RenderTexture prevFrame, flowBuffer, resultBuffer, sourceBuffer;

    #region MonoBehaviour functions

    protected void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (prevFrame == null)
        {
            Setup(source.width, source.height);
            Graphics.Blit(source, prevFrame);
        }

        Graphics.Blit(source, sourceBuffer);

        flowMaterial.SetTexture("_PrevTex", prevFrame);
        
        Graphics.Blit(source, flowBuffer, flowMaterial, 2);

        Graphics.Blit(flowBuffer, prevFrame);

        Graphics.Blit(flowBuffer, resultBuffer, flowMaterial, 3);

        Graphics.Blit(resultBuffer, destination);
    }

    protected void OnEnable()
    {
        flowMaterial = new Material(Shader.Find("Hidden/Kino/Damosh"));
        flowMaterial.hideFlags = HideFlags.DontSave;

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

        resultBuffer = new RenderTexture(width, height, 0);
        resultBuffer.format = RenderTextureFormat.ARGBFloat;
        resultBuffer.filterMode = FilterMode.Point;
        resultBuffer.Create();

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

            resultBuffer.Release();
            resultBuffer = null;
        }
    }

    protected void OnGUI()
    {
        if (prevFrame == null || flowBuffer == null) return;

        const int offset = 10;
        int width = Screen.width / 5, height = Screen.height / 5;
        GUI.DrawTexture(new Rect(offset, offset, width, height), sourceBuffer);
        GUI.DrawTexture(new Rect(offset, offset + height, width, height), flowBuffer);
    }


    #endregion
}
