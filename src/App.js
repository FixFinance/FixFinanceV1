import React from 'react';
import Navbar from './components/Navbar/index.tsx';
import { BrowserRouter as Router, Switch, Route } from 'react-router-dom';
import UIKit from './views/allComponents';
import About from './views/about.js';
import Landing from './views/landing';
import Community from './views/community';
import Wallet from './views/wallet';
import Margin from './views/margin';

function App() {
  return (
    <Router>
      <Navbar />
      <Switch>
        <Route path='/' exact component={Landing} />
        <Route path='/browse_bonds' exact component={About} />
        <Route path='/docs' exact component={UIKit} />
        <Route path='/margin_systems' exact component={Margin} />
        <Route path='/community' exact component={Community} />
        <Route path='/wallet' exact component={Wallet} />
      </Switch>
    </Router>
  );
}

export default App;