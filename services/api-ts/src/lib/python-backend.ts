export async function fetchFromPython(path: string, init?: RequestInit): Promise<Response> {
  const baseUrl = process.env.VOXLOG_PY_BACKEND_URL || "http://127.0.0.1:7890";
  const token = process.env.VOXLOG_PY_BACKEND_API_TOKEN || "";
  const headers = new Headers(init?.headers || {});
  if (token) {
    headers.set("Authorization", `Bearer ${token}`);
  }
  return fetch(`${baseUrl}${path}`, {
    ...init,
    headers
  });
}

export async function parsePythonJson<T = unknown>(response: Response): Promise<T> {
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`python backend ${response.status}: ${text || response.statusText}`);
  }
  return (await response.json()) as T;
}

export async function getJsonFromPython<T = unknown>(path: string): Promise<T> {
  const response = await fetchFromPython(path);
  return parsePythonJson<T>(response);
}

export async function postFormToPython<T = unknown>(
  path: string,
  form: Record<string, string>
): Promise<T> {
  const response = await fetchFromPython(path, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(form).toString()
  });
  return parsePythonJson<T>(response);
}

export async function postJsonToPython<T = unknown>(
  path: string,
  body: unknown
): Promise<T> {
  const response = await fetchFromPython(path, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body)
  });
  return parsePythonJson<T>(response);
}
