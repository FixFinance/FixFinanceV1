import {
    H4Text,
    Container,
    BoxText,
    Box,
    BoxHeader,
    BoxHeaderCol,
    CryptoIcon,
    BoxBody,
    BoxTitle,
    BorderText,
    AllBond,
    Bond,
    BondColumn,
    AllBondHeader,
    BodyText
  } from '../components/Components'
  
  import logo from '../assets/logo.png';
  
  function BrowseBonds() {
    var allBondsRows = [];
    var featuredBondsRows = [];
  
    for (var i = 0; i < 100; i++) {
      allBondsRows.push(          
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
          </Bond>)
    };
  
    for (var a = 0; a < 3; a++) {
      featuredBondsRows.push(          
        <Box>
          <BoxHeader>
            <BoxHeaderCol>
              <CryptoIcon src={logo} alt="Crytpocurrency Icon" />
              aUSDC
            </BoxHeaderCol>
            <BoxHeaderCol>
              AAVE
            </BoxHeaderCol>
            <BoxHeaderCol>
              12% APY
            </BoxHeaderCol>
            <BoxHeaderCol color='green'>
              +0.2%
            </BoxHeaderCol>
          </BoxHeader>
          <BoxBody>
            <BorderText>
              Maturity Date
            </BorderText>
            <BoxTitle white textAlign="start">
              Jan 19, 2022
            </BoxTitle>
            <BoxText white textAlign="start">
              If you invest X now, you will get Z in N months.
            </BoxText>
          </BoxBody>
        </Box>)
    };
  
    return (
      <Container black style={{'justifyContent':'flex-start'}}>
        <div style={{'width':'100vw'}}>
          <H4Text style={{'textAlign':'start', 'padding': '50px'}} white>Featured Bonds</H4Text>
          <div style={{'display':'flex', 'alignItems':'start', 'paddingInline': '50px', 'paddingBottom': '80px'}}>
            {featuredBondsRows}
          </div>
          <H4Text style={{'textAlign':'start', 'padding': '50px'}} white>All Bonds</H4Text>
          <AllBond>
            <AllBondHeader>
              <p>Assets</p>
              <p>Ecosystem</p>
              <p>Maturity Date</p>
              <p>APY</p>
            </AllBondHeader>
            {allBondsRows}
          </AllBond>
        </div>
      </Container>
    )
  }
  
  export default BrowseBonds; 