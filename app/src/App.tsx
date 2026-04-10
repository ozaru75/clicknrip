import { createSignal } from "solid-js";
import { Home } from "./pages/Home";
import { Router, Route } from "@solidjs/router";

function App() {
  return (
    <>
      <Router>
        <Route path="/" component={Home} />
      </Router>
    </>
  );
}

export default App;
