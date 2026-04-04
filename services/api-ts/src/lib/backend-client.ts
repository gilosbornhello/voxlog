import {
  fetchFromPython,
  getJsonFromPython,
  parsePythonJson,
  postFormToPython,
  postJsonToPython
} from "./python-backend.js";

export interface BackendClient {
  fetchFromPython: typeof fetchFromPython;
  getJsonFromPython: typeof getJsonFromPython;
  parsePythonJson: typeof parsePythonJson;
  postFormToPython: typeof postFormToPython;
  postJsonToPython: typeof postJsonToPython;
}

export const pythonBackendClient: BackendClient = {
  fetchFromPython,
  getJsonFromPython,
  parsePythonJson,
  postFormToPython,
  postJsonToPython
};
