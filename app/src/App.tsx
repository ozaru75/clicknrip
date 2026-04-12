import { Home } from "./pages/Home";
import { Router, Route } from "@solidjs/router";
import { WalletProvider } from "./providers/WalletProvider";

function App() {
  return (
    <WalletProvider>
      <Router>
        <Route path="/" component={Home} />
      </Router>
    </WalletProvider>
  );
}

export default App;
