import React from 'react';
import Navbar from './components/Navbar/index';
import { BrowserRouter as Router, Switch, Route } from 'react-router-dom';
import UIKit from './pages/allComponents';
import Landing from './pages/landing';
import Community from './pages/community';
import Bonds from './pages/bonds';
import Wallet from './pages/testWallet';
import Margin from './pages/margin';
import { Web3Provider } from '@ethersproject/providers';
import { Web3ReactProvider } from '@web3-react/core';

function getLibrary(provider: any): Web3Provider {
  const library = new Web3Provider(provider)
  library.pollingInterval = 12000
  return library
}

function App() {
  return (
    <Web3ReactProvider getLibrary={getLibrary}>
      <Router>
        <Navbar />
        <Switch>
          <Route path='/' exact component={Landing} />
          <Route path='/browse_bonds' exact component={Bonds} />
          <Route path='/docs' exact component={UIKit} />
          <Route path='/margin_systems' exact component={Margin} />
          <Route path='/community' exact component={Community} />
          <Route path='/wallet' exact component={Wallet} />
        </Switch>
      </Router>
    </Web3ReactProvider>
  );
}

export default App;