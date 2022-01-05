import React from 'react';
import {
  FooterIcon,
  Nav,
} from './FooterElements';

import {ReactComponent as ReactLogo} from '../../assets/fi.svg';

const Footer = () => {
  return (
    <Nav>
      <FooterIcon>
        <ReactLogo />
      </FooterIcon>
    </Nav>
  );
};

export default Footer; 