import React, { useContext } from 'react';
import { Button, Container, H1Text } from '../components/Components';
import {GlobalContext} from '../context/GlobalState';

const Bonds = () => {
  const { NGBwrapper } = useContext(GlobalContext);

  return (
    <Container>
      {/* <H1Text white>
        Browse Bonds Page
      </H1Text> */}
      <Button>Test Deposit</Button>
    </Container>
  );
};
  
export default Bonds;