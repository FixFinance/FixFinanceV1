import React from 'react';
import Navbar from './components/Navbar/index';
import { BrowserRouter as Router, Switch, Route } from 'react-router-dom';
import UIKit from './views/allComponents';
import About from './views/bonds';
import Landing from './views/landing';
import Community from './views/community';
import Margin from './views/margin';
import Web3Tests from './views/web3Tests'
import { GlobalProvider } from './context/GlobalState';

function App() {
  return (
    <GlobalProvider>
      <Router>
        <Navbar />
        <Switch>
          <Route path='/' exact component={Landing} />
          <Route path='/browse_bonds' exact component={About} />
          <Route path='/docs' exact component={UIKit} />
          <Route path='/margin_systems' exact component={Margin} />
          <Route path='/community' exact component={Community} />
          <Route path='/web3_tests' exact component={Web3Tests} />
        </Switch>
      </Router>
    </GlobalProvider>
  );
}

export default App;