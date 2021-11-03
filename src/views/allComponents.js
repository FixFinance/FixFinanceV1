import React from 'react';
import {
  Button,
  H1Text,
  H2Text,
  H3Text,
  H4Text,
  H5Text,
  Container,
  BodyText,
  Bond,
  BondColumn,
  Dropdown,
  CryptoIcon,
  StyledSVG,
} from '../components/Components'

import logo from '../assets/logo.png';

function UIKit() {
  return (
    <Container style={{'background': 'white'}}>
      <H1Text>New way of investing</H1Text>
      <H2Text>New way of investing</H2Text>
      <H3Text>New way of investing</H3Text>
      <H4Text>New way of investing</H4Text>
      <H5Text>New way of investing</H5Text>
      <BodyText>Scelerisque dui, est pharetra a nascetur in mauris. Sit ornare diam fames amet pellentesque euismod ipsum enim eros. Consequat sem cras egestas a. Mauris sit facilisis pretium ultricies ornare nibh. Cursus luctus magna neque, tellus. Aliquam purus ut platea sed. Facilisis magna morbi imperdiet faucibus. Nibh enim elementum sagittis sed cursus nisl odio at. Aliquam ac porttitor eu eget mauris, aliquam eu, in maecenas. Sagittis, nulla platea sem euismod. Quisque tempor, pulvinar quis mauris ipsum. Eleifend amet ac eget augue. Nullam lectus condimentum odio et, varius laoreet mattis id. Arcu vitae ante bibendum arcu. Neque, ut ultrices nascetur fermentum urna massa faucibus.</BodyText>
      <Button>Browse Bonds</Button>
      <Button black>Browse Bonds</Button>
      <br/>
      <Bond>
        <BondColumn width="10%">
          <CryptoIcon src={logo} alt="Crytpocurrency Icon" />
          aUSDC
        </BondColumn>
        <BondColumn width="30%">
          AAVE
        </BondColumn>
        <BondColumn width="30%">
          Jan 19, 2022
        </BondColumn>
        <BondColumn width="30%">
          12%
        </BondColumn>
      </Bond>
      <br/>
      <Dropdown>
        <StyledSVG width="25" height="24" viewBox="0 0 25 24" fill="none" xmlns="http://www.w3.org/2000/svg">
          <g id="Iconly/Bold/Arrow - Down 2">
            <rect x="0.5" width="24" height="24" rx="12" fill="#0F1010"/>
            <path id="Polygon 1" d="M12.5 17L7.5 9L17.5 9L12.5 17Z"/>
          </g>
        </StyledSVG>      
        Dropdown Select
      </Dropdown>
      <br/>
    </Container>
  );
}

export default UIKit;
