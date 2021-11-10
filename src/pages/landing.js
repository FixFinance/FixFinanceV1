import {
  Button,
  H1Text,
  Container,
  BodyText
} from '../components/Components'

function Landing() {
  return (
    <Container>
      <H1Text white>New way of investing</H1Text>
      <BodyText white>fix finance allows both fixed rate borrowing and lending as well as the ability to gain leveraged exposure to variable yield with the use of YTs</BodyText>
      <div style={{'text-align':'center'}}> 
        <Button>Browse Bonds</Button>
        <Button black>Read Docs</Button>
      </div>
    </Container>
  )
}

export default Landing;