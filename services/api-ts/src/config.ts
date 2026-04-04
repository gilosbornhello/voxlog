export const config = {
  port: Number(process.env.VOXLOG_TS_PORT || "7891"),
  pythonBackendBaseUrl: process.env.VOXLOG_PY_BACKEND_URL || "http://127.0.0.1:7890",
  pythonBackendApiToken: process.env.VOXLOG_PY_BACKEND_API_TOKEN || ""
};
